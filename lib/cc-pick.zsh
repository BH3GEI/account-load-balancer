#!/bin/zsh
# 选择负载最低的 Claude Code 账号。标准输出只输出编号 N；用量表输出到标准错误。
#
# 数据来源：用量缓存 $ALB_STATE/cc-usage.cache（由 cc-usage.zsh 生成），叠加每个账号当前正在运行的 claude 会话数。
# 缓存不存在时同步刷新；缓存超过 ALB_REFRESH_AGE 秒时在后台刷新，本次仍使用旧缓存，不阻塞启动。
#
# 负载 = max(5 小时用量 + 正在运行的会话数 × ALB_PER_SESSION, 7 天用量)。
# 缓存生成已超过 5 小时，则 5 小时窗口必然已重置，按 0 计算。
# 7 天用量 ≥ ALB_FULL_PCT 或 5 小时用量 ≥ 100 的账号视为已满，不会被自动选中。
# 用法：cc-pick.zsh [--refresh]
emulate -L zsh
setopt null_glob
source ${0:A:h}/common.zsh

refresh=0
[[ $1 == --refresh ]] && refresh=1
cache=$ALB_STATE/cc-usage.cache
usage_script=${0:A:h}/cc-usage.zsh

age() {
  local ts
  ts=$(head -n 1 $cache 2>/dev/null | awk '{print $4}')
  [[ $ts == <-> ]] || { print 999999; return }
  print $(( $(date +%s) - ts ))
}

# 缓存中没有任何可用（ok）账号时，后台刷新来不及，先同步刷新一次再选择
if (( ! refresh )) && [[ -f $cache ]] && ! awk '!/^#/ && $4 == "ok" {f=1} END {exit !f}' $cache; then
  print -u2 'cc-pick：缓存中没有可用账号，正在同步刷新用量（约 20 秒）。'
  refresh=1
fi

if (( refresh )) || [[ ! -f $cache ]]; then
  # 已有刷新在进行（锁目录存在）时 cc-usage.zsh 会直接退出，因此先等待其结束（最多 120 秒）
  for i in {1..120}; do [[ -d $ALB_STATE/cc-usage.lock ]] || break; sleep 1; done
  zsh $usage_script || exit 1
elif (( $(age) > ALB_REFRESH_AGE )); then
  ( zsh $usage_script >/dev/null 2>&1 & ) &>/dev/null
fi

# 多个 cc0 同时启动时，用文件锁让选号依次进行；每次选号记录一条「预约」，
# 之后 ALB_RESERVE_WINDOW 秒内的选号把这些预约也计为正在运行的会话（此时 claude 进程可能尚未出现）。
reserve_log=$ALB_STATE/cc-reserve.log
zmodload zsh/system
exec {lockfd}>>$ALB_STATE/cc-pick.lock
zsystem flock -f lockfd -t 15 $ALB_STATE/cc-pick.lock 2>/dev/null   # 拿不到锁时继续执行，只是不排队

# 每个账号当前正在运行的 claude 会话数（按进程环境中的 CLAUDE_CONFIG_DIR 识别），加上最近的预约
typeset -A live
nowts=$(date +%s)
if [[ -f $reserve_log ]]; then
  awk -v t=$(( nowts - ALB_RESERVE_WINDOW )) '$2 >= t' $reserve_log > $reserve_log.tmp && mv $reserve_log.tmp $reserve_log
  while read -r k ts; do live[$k]=$(( ${live[$k]:-0} + 1 )); done < $reserve_log
fi
for pid in $(ps -Ao pid=,comm= | awk '$2 ~ /(^|\/)claude$/ {print $1}'); do
  d=$(ps eww -o command= -p $pid 2>/dev/null | grep -o 'CLAUDE_CONFIG_DIR=[^ ]*' | head -n 1)
  d=${d#CLAUDE_CONFIG_DIR=}
  [[ $d == ${(b)ALB_BASE}/.claude-cc<-> ]] || continue
  k=${d##*.claude-cc}
  live[$k]=$(( ${live[$k]:-0} + 1 ))
done
live_arg=""
for k in ${(k)live}; do live_arg+="$k:${live[$k]},"; done

tmp=$(mktemp) || exit 1
trap 'rm -f $tmp' EXIT

# 排序键：可用账号按负载排序（越小越优先）；闲置、令牌过期、查询失败、不可用依次排在后面
awk -v live="$live_arg" -v per=$ALB_PER_SESSION -v full=$ALB_FULL_PCT -v age=$(age) '
  BEGIN { m = split(live, a, ","); for (i = 1; i <= m; i++) if (split(a[i], b, ":") == 2) L[b[1]] = b[2] }
  /^#/ { next }
  NF >= 4 { n=$1; h=$2; w=$3; st=$4; s = L[n] + 0
    if (st == "ok") {
      if (age > 18000) h = 0
      if (h >= 100 || w >= full) key = 300000000 + (h > w ? h : w)
      else { e = h + s * per; if (e > 99) e = 99
             key = (((e > w ? e : w) * 1000) + w) * 1000 + h }
    } else if (st == "idle")                      key = 150000000
    else if (st == "expired" || st == "stale") key = 200000000
    else                                          key = 900000000
    printf "%d %s %s %s %s %d\n", key, n, h, w, st, s }' $cache | sort -n -k1,1 -k2,2 > $tmp

gen=$(head -n 1 $cache | sed -n 's/^# generated \([^ ]*\).*/\1/p')
{
  printf '  用量缓存生成于 %s（%s 小时前）\n' "${gen:-未知}" "$(( $(age) / 3600 ))"
  printf '  %-6s %6s %6s %6s\n' 账号 5h 7d 运行中
  while read -r key n h w st s; do
    if [[ $st == ok ]]; then
      printf '  %-6s %5s%% %5s%% %6s\n' "cc$n" $h $w $s
    else
      case $st in
        (idle) st='闲置（下次启动时自动续期）' ;;
        (expired) st='令牌已过期，需要重新登录' ;;
        (stale) st='查询失败' ;;
        (disabled) st='不可用（所在组织禁用了订阅访问）' ;;
        (nologin) st='未登录' ;;
      esac
      printf '  %-6s %s\n' "cc$n" $st
    fi
  done < $tmp
} >&2

read -r key n _ < $tmp
if [[ -z $n ]]; then
  print -u2 'cc-pick：用量缓存为空。请先运行 cc-usage，或确认已登录至少一个账号。'
  exit 1
fi
if (( key < 100000000 )); then
  print "$n $nowts" >> $reserve_log
  print $n
  exit 0
fi
# 没有确认有余量的账号时，依次退而选择闲置的账号、状态未知的账号（令牌过期或查询失败，用量未知）
unknown=$(awk '$1 >= 150000000 && $1 < 210000000 { print $2; exit }' $tmp)
if [[ -n $unknown ]]; then
  print -u2 "cc-pick：没有确认有余量的账号，改为选择用量未知的 cc$unknown。"
  print "$unknown $nowts" >> $reserve_log
  print $unknown
  exit 0
fi
print -u2 'cc-pick：没有可用账号（见上表）。可以直接运行 cc1 … ccN 指定账号。'
exit 1
