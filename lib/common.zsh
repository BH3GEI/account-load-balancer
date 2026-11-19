# account-load-balancer：所有脚本共用的设置。
# 用户自己的取值写在 $ALB_CONFIG（默认 ~/.config/account-load-balancer/config.zsh），这里只给默认值。

ALB_CONFIG=${ALB_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/account-load-balancer/config.zsh}
[[ -r $ALB_CONFIG ]] && source $ALB_CONFIG

: ${ALB_BASE:=$HOME}                       # 各账号配置目录（.claude-ccN、.codex-cxN）所在的目录
: ${ALB_STATE:=${XDG_STATE_HOME:-$HOME/.local/state}/account-load-balancer}   # 用量缓存、锁、日志
: ${ALB_CLAUDE_ACCOUNTS:=6}                # Claude Code 账号数量：定义 cc1 … ccN
: ${ALB_CODEX_ACCOUNTS:=6}                 # Codex 账号数量：定义 cx1 … cxN
: ${ALB_TOKEN_SERVICE:=cc-longtoken-}      # 长期令牌在 macOS 钥匙串中的服务名前缀（服务名 = 前缀 + 编号）
: ${ALB_USAGE_MODEL:=haiku}                # 查询 Claude 用量时发送最小请求所用的模型
: ${ALB_REFRESH_AGE:=1800}                 # Claude 用量缓存超过多少秒后在后台刷新
: ${ALB_PER_SESSION:=15}                   # 每个正在运行的 Claude 会话折算为多少个百分点的 5 小时用量
: ${ALB_FULL_PCT:=95}                      # Claude 7 天用量达到该百分比即视为已满
: ${ALB_RESERVE_WINDOW:=30}                # 选号后多少秒内，该次选号仍计为一个正在运行的会话
: ${ALB_WORKDIR:=}                         # 非空时，ccN / cxN 在该目录中启动（当前目录已在其中则不切换）
: ${ALB_KEEP_SESSIONS:=0}                  # 为 1 时，把 Claude 的 cleanupPeriodDays 设为 99999，不自动清理旧会话
(( ${+ALB_CLAUDE_ARGS} )) || typeset -ga ALB_CLAUDE_ARGS=()   # 启动 claude 时附加的参数
(( ${+ALB_CODEX_ARGS} )) || typeset -ga ALB_CODEX_ARGS=()     # 启动 codex 时附加的参数

mkdir -p $ALB_STATE 2>/dev/null

# 第 n 个 Claude 账号的长期令牌（claude setup-token 生成）：macOS 从钥匙串读取，其他系统从 $ALB_STATE/tokens/claude-<n> 读取。
_alb_token() {
  local n=$1
  if [[ $OSTYPE == darwin* ]]; then
    security find-generic-password -s ${ALB_TOKEN_SERVICE}$n -w 2>/dev/null
  elif [[ -r $ALB_STATE/tokens/claude-$n ]]; then
    < $ALB_STATE/tokens/claude-$n
  fi
}

# 第 n 个 Claude 账号经 /login 保存的登录信息（JSON）。macOS 存在钥匙串中，服务名由配置目录路径决定；其他系统存在配置目录的 .credentials.json 中。
_alb_credentials() {
  local dir=$1
  if [[ $OSTYPE == darwin* ]]; then
    security find-generic-password -s "Claude Code-credentials-$(printf %s "$dir" | shasum -a 256 | cut -c1-8)" -w 2>/dev/null
  elif [[ -r $dir/.credentials.json ]]; then
    < $dir/.credentials.json
  fi
}
