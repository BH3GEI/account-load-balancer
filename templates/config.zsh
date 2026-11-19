# account-load-balancer 的设置。修改后新开一个终端即可生效。
# 每一项都有默认值，只需取消注释并修改需要改变的项。

# 账号数量：分别定义 cc1 … ccN 和 cx1 … cxN
# ALB_CLAUDE_ACCOUNTS=6
# ALB_CODEX_ACCOUNTS=6

# 各账号配置目录（.claude-ccN、.codex-cxN）所在的目录
# ALB_BASE=$HOME

# 启动时附加的参数，例如跳过权限确认（请确认你了解其含义）
# ALB_CLAUDE_ARGS=(--dangerously-skip-permissions)
# ALB_CODEX_ARGS=(--dangerously-bypass-approvals-and-sandbox)

# 非空时，ccN / cxN 在该目录中启动（当前目录已在其中则不切换）
# ALB_WORKDIR=$HOME/work

# 为 1 时，Claude 不自动清理 30 天前的旧会话
# ALB_KEEP_SESSIONS=0

# 选号参数
# ALB_REFRESH_AGE=1800      # Claude 用量缓存超过多少秒后在后台刷新
# ALB_PER_SESSION=15        # 每个正在运行的 Claude 会话折算为多少个百分点的 5 小时用量
# ALB_FULL_PCT=95           # Claude 7 天用量达到该百分比即视为已满
# ALB_RESERVE_WINDOW=30     # 选号后多少秒内，该次选号仍计为一个正在运行的会话

# 长期令牌在 macOS 钥匙串中的服务名前缀（服务名 = 前缀 + 编号）
# ALB_TOKEN_SERVICE=cc-longtoken-

# 查询 Claude 用量时发送最小请求所用的模型
# ALB_USAGE_MODEL=haiku

# 用量缓存、锁和日志的位置
# ALB_STATE=$HOME/.local/state/account-load-balancer
