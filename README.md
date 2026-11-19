# account-load-balancer（账号负载均衡）

在同一台机器上并行使用多个 Claude Code 账号和多个 Codex 账号，并在启动时自动选择当前用量最低的账号。

- `cc1` … `cc6`：分别以第 1 … 6 个 Claude Code 账号启动 `claude`，各账号使用独立的配置目录，登录状态互不影响。
- `cx1` … `cx6`：分别以第 1 … 6 个 Codex 账号启动 `codex`。
- `cc0`：查询各 Claude 账号的 5 小时和 7 天限额用量，叠加当前正在运行的会话数，选择负载最低的账号启动。
- `cx0`：查询各 Codex 账号的用量，选择用量最低的账号启动。
- `cc-usage`：立即刷新 Claude 账号的用量缓存，并显示用量表。

账号数量、启动参数、选号规则均可在设置文件中修改。

## 部署

依赖：zsh、jq、curl、perl，以及 [Claude Code](https://docs.anthropic.com/claude-code) 和/或 [Codex CLI](https://github.com/openai/codex)。支持 macOS 和 Linux。

```sh
git clone https://github.com/BH3GEI/account-load-balancer.git
cd account-load-balancer
./install.sh              # 如需每天自动刷新 Claude 用量：./install.sh --schedule
exec zsh                  # 重新加载 shell
```

`install.sh` 完成以下操作，可重复运行：

1. 把脚本复制到 `~/.local/share/account-load-balancer/`；
2. 创建设置文件 `~/.config/account-load-balancer/config.zsh`（已存在时保留）；
3. 在 `~/.zshrc` 末尾加入一行 `source …/alb.zsh`（已存在时不重复加入）；
4. 使用 `--schedule` 时，安装每天 09:30 刷新 Claude 用量的定时任务（macOS 为 launchd，Linux 为 systemd 用户定时器）。

### 登录账号

Claude Code，每个账号任选一种方式：

- 交互登录：运行 `cc1`，在其中输入 `/login`，在浏览器中登录第 1 个账号；`cc2` … 同理。
- 长期令牌（推荐，有效期一年，不需要定期重新登录）：在该账号下运行 `claude setup-token` 得到令牌，然后保存：
  - macOS：`security add-generic-password -s cc-longtoken-1 -a "$USER" -w '<令牌>'`（第 N 个账号使用 `cc-longtoken-N`）
  - Linux：`install -m 600 /dev/stdin ~/.local/state/account-load-balancer/tokens/claude-1 <<< '<令牌>'`

Codex：运行 `cx1 login`，在浏览器中登录第 1 个账号；`cx2 login` … 同理。

登录后运行 `cc0` 或 `cx0` 即可。

### 卸载

```sh
./uninstall.sh
```

删除脚本、定时任务和 `~/.zshrc` 中的 source 行；保留设置文件、用量缓存和各账号的登录信息。

## 使用

```text
$ cc0
  用量缓存生成于 2026-11-19T06:07:12Z（0 小时前）
  账号         5h     7d    运行中
  cc6        1%    13%      3
  cc4        5%    28%      3
  cc5        0%    97%      1
  cc3        0%   100%      4
→ cc6
```

用量表和「→ cc6」输出到标准错误，之后与直接运行 `cc6` 相同。所有参数原样传给 `claude` / `codex`，例如 `cc0 -p "问题"`、`cx0 exec "任务"`。

其他程序可以读取标准错误中的「→ ccN」一行，得知实际使用的账号。

## 选号规则

### Claude（cc0）

1. 用量来自缓存 `~/.local/state/account-load-balancer/cc-usage.cache`。缓存不存在时同步刷新；超过 30 分钟时在后台刷新，本次仍使用旧缓存，不阻塞启动。
2. 每个账号的负载 = max(5 小时用量 + 正在运行的会话数 × 15, 7 天用量)。正在运行的会话按进程环境中的 `CLAUDE_CONFIG_DIR` 识别。缓存生成已超过 5 小时时，5 小时用量按 0 计算。
3. 选择负载最低的账号。5 小时用量达到 100% 或 7 天用量达到 95% 的账号视为已满，不会被选中。
4. 每次选号都会记录一次预约，30 秒内的后续选号把它计为一个正在运行的会话。因此同时启动多个 `cc0` 时，会话会分散到不同账号。
5. 没有确认有余量的账号时，依次退而选择闲置的账号、用量未知的账号；仍没有时返回失败。

用量的查询方式：

- 有长期令牌的账号：发送一次最小请求（默认模型 haiku），从返回的 `rate_limit_event` 中读取用量。各账号并行查询，约 20 秒。
- 交互登录的账号：调用 Claude 的用量接口读取。访问令牌已过期时不发请求，标为「闲置」（下次启动时会自动续期）。

账号状态：

| 状态 | 含义 |
|---|---|
| 百分比 | 已取得用量 |
| 闲置 | 访问令牌已过期但可以自动续期，用量未知 |
| 令牌已过期 | 需要重新 `/login` |
| 查询失败 | 请求失败或返回内容中没有用量（限流、网络问题、令牌被吊销） |
| 不可用 | 账号所在组织禁用了 Claude Code 的订阅访问 |
| 未登录 | 没有该账号的登录信息 |

### Codex（cx0）

每次启动时并行查询各账号的 5 小时和 7 天用量，不使用缓存。先比较 max(5h, 7d)，再比较 7d，再比较 5h；任一项达到 100% 的账号排在最后。访问令牌已过期的账号，直接运行一次 `cxN` 即会自动刷新。

## 设置

设置文件 `~/.config/account-load-balancer/config.zsh` 中列出了全部设置项及默认值，取消注释即可修改，新开终端后生效。

| 设置项 | 默认值 | 说明 |
|---|---|---|
| `ALB_CLAUDE_ACCOUNTS` | 6 | Claude 账号数量，定义 cc1 … ccN |
| `ALB_CODEX_ACCOUNTS` | 6 | Codex 账号数量，定义 cx1 … cxN |
| `ALB_BASE` | `$HOME` | 各账号配置目录（`.claude-ccN`、`.codex-cxN`）所在的目录 |
| `ALB_CLAUDE_ARGS` | 空 | 启动 claude 时附加的参数，例如 `(--dangerously-skip-permissions)` |
| `ALB_CODEX_ARGS` | 空 | 启动 codex 时附加的参数 |
| `ALB_WORKDIR` | 空 | 非空时，ccN / cxN 在该目录中启动 |
| `ALB_KEEP_SESSIONS` | 0 | 为 1 时，Claude 不自动清理 30 天前的旧会话 |
| `ALB_REFRESH_AGE` | 1800 | Claude 用量缓存超过多少秒后在后台刷新 |
| `ALB_PER_SESSION` | 15 | 每个正在运行的 Claude 会话折算为多少个百分点的 5 小时用量 |
| `ALB_FULL_PCT` | 95 | Claude 7 天用量达到该百分比即视为已满 |
| `ALB_RESERVE_WINDOW` | 30 | 选号后多少秒内，该次选号仍计为一个正在运行的会话 |
| `ALB_TOKEN_SERVICE` | `cc-longtoken-` | 长期令牌在 macOS 钥匙串中的服务名前缀 |
| `ALB_USAGE_MODEL` | haiku | 查询 Claude 用量时发送最小请求所用的模型 |
| `ALB_STATE` | `~/.local/state/account-load-balancer` | 用量缓存、锁和日志的位置 |

## 文件

| 位置 | 内容 |
|---|---|
| `~/.local/share/account-load-balancer/` | 脚本 |
| `~/.config/account-load-balancer/config.zsh` | 设置 |
| `~/.local/state/account-load-balancer/` | 用量缓存、选号锁、预约记录、定时任务日志 |
| `~/.claude-ccN/`、`~/.codex-cxN/` | 各账号的配置目录 |

## 安全

- 本工具不保存任何密码。长期令牌在 macOS 上只存放在系统钥匙串中，在 Linux 上存放在权限为 600 的文件中；令牌只通过环境变量传给 `claude`，不写入日志和缓存。
- 用量查询只读取用量，不修改账号。
- `ALB_CLAUDE_ARGS` 和 `ALB_CODEX_ARGS` 默认为空，不会跳过任何权限确认。

## 测试

```sh
zsh tests/run.zsh
```

测试使用替身代替 curl、claude 和 security，不访问网络，也不读取真实账号。

## 许可

MIT
