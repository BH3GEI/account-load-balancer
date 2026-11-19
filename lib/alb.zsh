# account-load-balancer：在 ~/.zshrc 中 source 本文件。
# 定义 cc1 … ccN（各 Claude Code 账号）、cx1 … cxN（各 Codex 账号），
# 以及 cc0 / cx0（自动选择当前用量最低的账号再启动）和 cc-usage（立即刷新 Claude 用量）。

_alb_dir=${${(%):-%x}:A:h}
source $_alb_dir/common.zsh

# 启动第 n 个 Claude Code 账号：每个账号使用独立的配置目录 $ALB_BASE/.claude-cc<n>，登录状态互不影响。
claude-cc() {
  local n=$1; shift
  local dir=$ALB_BASE/.claude-cc$n
  mkdir -p $dir
  if (( ALB_KEEP_SESSIONS )); then
    local cfg=$dir/settings.json
    if [[ ! -f $cfg ]]; then
      print '{"cleanupPeriodDays": 99999}' > $cfg
    elif ! jq -e 'has("cleanupPeriodDays")' $cfg >/dev/null 2>&1; then
      jq '.cleanupPeriodDays = 99999' $cfg > $cfg.tmp && mv $cfg.tmp $cfg
    fi
  fi
  (
    [[ -n $ALB_WORKDIR && -d $ALB_WORKDIR && $PWD/ != $ALB_WORKDIR/* ]] && builtin cd $ALB_WORKDIR
    # 有长期令牌就使用它；没有时 claude 使用该配置目录中 /login 保存的登录信息
    local tok; tok=$(_alb_token $n)
    [[ -n $tok ]] && export CLAUDE_CODE_OAUTH_TOKEN=$tok
    unset tok
    CLAUDE_CONFIG_DIR=$dir command claude "${ALB_CLAUDE_ARGS[@]}" "$@"
  )
}

# 启动第 n 个 Codex 账号：每个账号使用独立的 CODEX_HOME（$ALB_BASE/.codex-cx<n>）。cx<n> login 登录该账号。
codex-cx() {
  local n=$1; shift
  local home=$ALB_BASE/.codex-cx$n
  if [[ ! -f $home/config.toml ]]; then
    # 登录信息保存在文件中（而非系统钥匙串），各账号才能互相独立
    mkdir -p $home && print 'cli_auth_credentials_store = "file"' > $home/config.toml
    # 共用 ~/.codex/AGENTS.md 中的全局说明
    [[ -f $HOME/.codex/AGENTS.md && ! -e $home/AGENTS.md ]] && ln -s $HOME/.codex/AGENTS.md $home/AGENTS.md
  fi
  if [[ $1 == login ]]; then
    shift; CODEX_HOME=$home command codex login "$@"; return
  fi
  (
    [[ -n $ALB_WORKDIR && -d $ALB_WORKDIR && $PWD/ != $ALB_WORKDIR/* ]] && builtin cd $ALB_WORKDIR
    CODEX_HOME=$home command codex "${ALB_CODEX_ARGS[@]}" "$@"
  )
}

for _alb_n in {1..$ALB_CLAUDE_ACCOUNTS}; do eval "cc$_alb_n() { claude-cc $_alb_n \"\$@\" }"; done
for _alb_n in {1..$ALB_CODEX_ACCOUNTS}; do eval "cx$_alb_n() { codex-cx $_alb_n \"\$@\" }"; done
unset _alb_n

# 选出编号后，在标准错误输出「→ cc<n>」一行，便于调用方得知实际使用的账号。
cc0() { local n; n=$(zsh $_alb_dir/cc-pick.zsh </dev/null) || return 1; print -u2 "→ cc$n"; claude-cc $n "$@" }
cx0() { local n; n=$(zsh $_alb_dir/cx-pick.zsh </dev/null) || return 1; print -u2 "→ cx$n"; codex-cx $n "$@" }
cc-usage() { zsh $_alb_dir/cc-usage.zsh && zsh $_alb_dir/cc-pick.zsh >/dev/null }
