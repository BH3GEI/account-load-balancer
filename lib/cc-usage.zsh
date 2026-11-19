#!/bin/zsh
# 查询每个 Claude Code 账号（$ALB_BASE/.claude-cc<N>）的 5 小时和 7 天限额用量，写入 $ALB_STATE/cc-usage.cache。
#
# 缓存格式：
#   首行     # generated <ISO 时间> <epoch 秒>
#   数据行   <N> <5h 百分比> <7d 百分比> <状态> <epoch 秒>
# 状态：
#   ok        已取得用量（5 小时窗口尚未开始时按 0% 计）
#   idle      访问令牌已过期，但有刷新令牌：该账号只是近期未使用，下次启动时会自动续期。未发请求，用量未知
#   expired   访问令牌已过期且没有刷新令牌，需要重新 /login
#   disabled  账号所在组织禁用了 Claude Code 的订阅访问，cc0 不会选择
#   stale     请求失败或返回内容中没有用量（限流、网络问题、令牌被吊销）
#   nologin   没有该账号的登录信息
#
# 查询方式：
#   有长期令牌（claude setup-token）的账号：用该令牌发送一次最小请求，从 rate_limit_event 中读取用量。各账号并行查询。
#   使用 /login 登录的账号：调用 /api/oauth/usage 接口读取用量，依次查询。
emulate -L zsh
setopt null_glob
source ${0:A:h}/common.zsh

cache=$ALB_STATE/cc-usage.cache
tmp=$(mktemp) || exit 1
body=$(mktemp) || exit 1
trap 'rm -f $tmp $body' EXIT
now=$(date +%s)
printf '# generated %s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$now" > $tmp

# 防止并发刷新（cc0 会在后台触发刷新）；锁存在超过 5 分钟视为上次异常退出的残留
lock=$ALB_STATE/cc-usage.lock
if ! mkdir $lock 2>/dev/null; then
  if [[ -n $(find $lock -maxdepth 0 -mmin +5 2>/dev/null) ]]; then rm -rf $lock; mkdir $lock || exit 0
  else exit 0; fi
fi
outdir=$(mktemp -d) || exit 1
trap 'rm -f $tmp $body; rm -rf $lock $outdir' EXIT

# 定时任务（launchd、systemd）的 PATH 通常不含 claude 和 node 的安装位置，这里补上常见位置
for p in /opt/homebrew/bin /usr/local/bin $HOME/.local/bin; do
  [[ -d $p && :$PATH: != *:$p:* ]] && PATH=$p:$PATH
done
claude_bin=$(whence -p claude)
if [[ -z $claude_bin ]]; then
  print -u2 'cc-usage：找不到 claude 命令。'
  exit 1
fi

query_long() {
  local n=$1 dir=$2 long=$3 line
  line=$(cd $ALB_STATE; CLAUDE_CODE_OAUTH_TOKEN=$long CLAUDE_CONFIG_DIR=$dir \
    perl -e 'alarm 90; exec @ARGV' $claude_bin -p 'reply with exactly: ok' --model $ALB_USAGE_MODEL \
    --no-session-persistence --output-format stream-json --verbose 2>/dev/null |
    jq -r --arg n "$n" --arg now "$now" '
      if .type == "result" and ((.result // "") | test("disabled Claude subscription access")) then
        "\($n) - - disabled \($now)"
      else
      select(.type == "rate_limit_event") | .rate_limit_info.unifiedWindows
      | select(.seven_day.utilization != null)
      | "\($n) \(((.five_hour.utilization // 0) * 100) | floor) \((.seven_day.utilization * 100) | floor) ok \($now)"
      end' 2>/dev/null | tail -n 1)
  if [[ -n $line ]]; then print -r -- $line; else printf '%s - - stale %s\n' $n $now; fi > $outdir/$n
}

first=1
for dir in $ALB_BASE/.claude-cc<1->; do
  n=${dir##*/.claude-cc}
  long=$(_alb_token $n)
  if [[ -n $long ]]; then
    query_long $n $dir $long &
    unset long
    continue
  fi

  cred=$(_alb_credentials $dir)
  if [[ -z $cred ]]; then
    printf '%s - - nologin %s\n' $n $now > $outdir/$n
    continue
  fi
  tok=$(jq -r '.claudeAiOauth.accessToken // empty' <<<"$cred" 2>/dev/null)
  exp=$(jq -r '.claudeAiOauth.expiresAt // 0' <<<"$cred" 2>/dev/null)
  exp=${exp%%.*}
  (( exp > 1000000000000 )) && exp=$(( exp / 1000 ))   # 毫秒时间戳
  if [[ -z $tok ]]; then
    printf '%s - - nologin %s\n' $n $now > $outdir/$n
    continue
  fi
  if (( exp > 0 && exp <= now )); then
    if [[ -n $(jq -r '.claudeAiOauth.refreshToken // empty' <<<"$cred" 2>/dev/null) ]]; then
      printf '%s - - idle %s\n' $n $now > $outdir/$n
    else
      printf '%s - - expired %s\n' $n $now > $outdir/$n
    fi
    continue
  fi

  (( first )) || sleep 2      # 该接口对并发请求敏感，依次查询
  first=0
  code=$(curl -s -o $body -w '%{http_code}' -m 10 https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $tok" -H "anthropic-beta: oauth-2025-04-20")
  unset tok cred
  line=$(jq -r --arg n "$n" --arg now "$now" '
    if (.seven_day.utilization // null) == null then empty
    else "\($n) \((.five_hour.utilization // 0) | floor) \((.seven_day.utilization) | floor) ok \($now)"
    end' $body 2>/dev/null)
  if [[ -n $line ]]; then print -r -- $line; else printf '%s - - stale %s\n' $n $now; fi > $outdir/$n
done
wait

for f in $outdir/*(n); do cat $f >> $tmp; done
mv $tmp $cache
