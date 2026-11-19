#!/bin/zsh
# 测试：选号规则、预约、Codex 选号、用量查询、函数定义。不访问网络，不读取真实账号：
# curl、claude、security 均由 tests/stub 中的替身代替，所有文件都在临时目录中。
emulate -L zsh
root=${0:A:h:h}
fails=0
check() { if eval "$2"; then print "PASS $1"; else print "FAIL $1"; fails=$((fails+1)); fi }

work=$(mktemp -d)
trap 'rm -rf $work' EXIT
export ALB_CONFIG=$work/none.zsh ALB_BASE=$work/base ALB_STATE=$work/state
export PATH=$root/tests/stub:$PATH STUB_DIR=$work
export ZDOTDIR=$work   # 不读取本机的 ~/.zshenv，以免其中的 PATH 设置让真实命令排在替身之前
mkdir -p $ALB_BASE $ALB_STATE

cache() { { print "# generated 2026-01-01T00:00:00Z $(date +%s)"; print -l "$@"; } > $ALB_STATE/cc-usage.cache; rm -f $ALB_STATE/cc-reserve.log; }
pick() { zsh $root/lib/cc-pick.zsh 2>$work/err }

# ---- Claude 选号
cache '1 50 60 ok 0' '2 10 20 ok 0' '3 - - idle 0' '4 100 40 ok 0' '5 - - expired 0'
check '选择负载最低的账号' '[[ $(pick) == 2 ]]'
check '用量表输出到标准错误，标准输出只有编号' 'grep -q "cc2" $work/err && [[ $(pick | wc -l | tr -d " ") == 1 ]]'
cache '1 50 60 ok 0' '2 10 20 ok 0'
seq=(); for i in 1 2 3 4 5; do seq+=$(pick); done
check '连续选号时，先前的选号计为运行中的会话，负载随之上升，最终换到另一个账号' '[[ ${(j: :)seq} == "2 2 2 2 1" ]]'
cache '1 100 100 ok 0' '2 - - idle 0' '3 - - expired 0'
check '没有余量时，退而选择闲置的账号' '[[ $(pick) == 2 ]]'
cache '1 100 100 ok 0' '3 - - expired 0'
check '其次选择用量未知的账号' '[[ $(pick) == 3 ]]'
cache '1 100 100 ok 0' '2 50 96 ok 0'
check '都已用满时不选择，返回失败' '! pick >/dev/null'
{ print "# generated 2026-01-01T00:00:00Z $(( $(date +%s) - 20000 ))"; print '1 90 30 ok 0'; print '2 10 50 ok 0'; } > $ALB_STATE/cc-usage.cache; rm -f $ALB_STATE/cc-reserve.log
mkdir -p $ALB_STATE/cc-usage.lock   # 视为已有刷新在进行，阻止后台刷新改动缓存
check '缓存超过 5 小时，5 小时用量视为已重置' '[[ $(pick) == 1 ]]'
rmdir $ALB_STATE/cc-usage.lock

# ---- Claude 用量查询
mkdir -p $ALB_BASE/.claude-cc1 $ALB_BASE/.claude-cc2 $ALB_BASE/.claude-cc3 $ALB_BASE/.claude-cc4 $ALB_STATE/tokens
print 'long-1' > $ALB_STATE/tokens/claude-1                    # 非 macOS 时的长期令牌位置
future=$(( ($(date +%s) + 3600) * 1000 ))
print "{\"claudeAiOauth\":{\"accessToken\":\"acc-2\",\"expiresAt\":$future}}" > $ALB_BASE/.claude-cc2/.credentials.json
print '{"claudeAiOauth":{"accessToken":"acc-3","expiresAt":1000,"refreshToken":"r"}}' > $ALB_BASE/.claude-cc3/.credentials.json
zsh $root/lib/cc-usage.zsh
c=$(cat $ALB_STATE/cc-usage.cache)
check '长期令牌账号：从 rate_limit_event 读取用量' '[[ $c == *$'"'"'\n1 12 34 ok'"'"'* ]]'
check '/login 账号：从用量接口读取用量' '[[ $c == *$'"'"'\n2 7 45 ok'"'"'* ]]'
check '令牌过期但可续期的账号标为闲置' '[[ $c == *$'"'"'\n3 - - idle'"'"'* ]]'
check '没有登录信息的账号标为未登录' '[[ $c == *$'"'"'\n4 - - nologin'"'"'* ]]'

# ---- Codex 选号
for n in 1 2 3; do mkdir -p $ALB_BASE/.codex-cx$n; print "{\"tokens\":{\"access_token\":\"cx-$n\",\"account_id\":\"a$n\"}}" > $ALB_BASE/.codex-cx$n/auth.json; done
check 'Codex：选择用量最低的账号' '[[ $(zsh $root/lib/cx-pick.zsh 2>$work/cxerr) == 2 ]]'
check 'Codex：令牌过期的账号在用量表中注明' 'grep -q "cx3 *令牌已过期" $work/cxerr'

# ---- 函数定义
check 'source alb.zsh 后按设置的数量定义 ccN、cxN、cc0、cx0' 'ALB_CLAUDE_ACCOUNTS=3 ALB_CODEX_ACCOUNTS=2 zsh -c "source $root/lib/alb.zsh; whence -w cc3 cx2 cc0 cx0 cc-usage >/dev/null && ! whence -w cc4 >/dev/null && ! whence -w cx3 >/dev/null"'

print
(( fails == 0 )) && print 'ALL PASS' || { print "$fails FAILED"; exit 1 }
