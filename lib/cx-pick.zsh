#!/bin/zsh
# 在各 Codex 账号（$ALB_BASE/.codex-cx<N>）中选择 5 小时和 7 天限额用量最低的一个。
# 标准输出只输出编号 N；用量表输出到标准错误。每次实时查询，不使用缓存。
#
# 排序：先比较 max(5h, 7d)，再比较 7d，再比较 5h；任一项达到 100% 的账号排在最后；查询失败的账号排在它们之前。
# 访问令牌有效期约 10 天，长期未使用的账号会显示「令牌已过期」，直接运行一次 cx<N> 即会自动刷新。
emulate -L zsh
setopt null_glob
source ${0:A:h}/common.zsh

tmp=$(mktemp -d) || exit 1
trap 'rm -rf $tmp' EXIT

query() {  # $1 = 编号，$2 = CODEX_HOME
  local n=$1 dir=$2 tok acc out code
  tok=$(jq -r '.tokens.access_token // empty' $dir/auth.json 2>/dev/null)
  acc=$(jq -r '.tokens.account_id // empty' $dir/auth.json 2>/dev/null)
  [[ -z $tok ]] && { print "$n - - nologin" > $tmp/$n; return; }
  out=$(curl -s -m 8 -w '\n%{http_code}' https://chatgpt.com/backend-api/wham/usage \
    -H "Authorization: Bearer $tok" -H "chatgpt-account-id: $acc" -H "User-Agent: codex_cli_rs")
  code=${out##*$'\n'}; out=${out%$'\n'*}
  if [[ $code == 401 ]]; then
    print "$n - - expired" > $tmp/$n
  elif jq -e '.rate_limit.primary_window and .rate_limit.secondary_window' <<<"$out" >/dev/null 2>&1; then
    jq -r --arg n $n '"\($n) \(.rate_limit.primary_window.used_percent|floor) \(.rate_limit.secondary_window.used_percent|floor) ok"' <<<"$out" > $tmp/$n
  else
    print "$n - - error" > $tmp/$n     # 限流、网络问题或接口格式变化
  fi
}

for dir in $ALB_BASE/.codex-cx<1->; do
  query ${dir##*/.codex-cx} $dir &
done
wait

cat $tmp/<->(N) | awk '
  { n=$1; h=$2; w=$3; st=$4
    if (st == "nologin")           key = 900000000
    else if (st != "ok")           key = 200000000
    else if (h >= 100 || w >= 100) key = 300000000 + (h > w ? h : w)
    else                           key = ((h > w ? h : w) * 1000 + w) * 1000 + h
    printf "%d %s %s %s %s\n", key, n, h, w, st }' | sort -n -k1,1 -k2,2 > $tmp/ranked

{
  printf '  %-6s %6s %6s\n' 账号 5h 7d
  while read -r key n h w st; do
    if [[ $st == ok ]]; then
      printf '  %-6s %5s%% %5s%%\n' "cx$n" $h $w
    else
      case $st in
        (expired) st='令牌已过期，运行一次 cx'$n' 即可刷新' ;;
        (error) st='查询失败' ;;
        (nologin) st='未登录' ;;
      esac
      printf '  %-6s %s\n' "cx$n" $st
    fi
  done < $tmp/ranked
} >&2

read -r key n _ < $tmp/ranked
if [[ -z $n || $key -ge 900000000 ]]; then
  print -u2 'cx-pick：没有可用账号。请先运行 cx1 login 登录。'
  exit 1
fi
print $n
