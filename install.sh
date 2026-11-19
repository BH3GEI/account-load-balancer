#!/bin/zsh
# 安装 account-load-balancer。
#   ./install.sh              安装到 ~/.local/share/account-load-balancer，并在 ~/.zshrc 中加入一行 source
#   ./install.sh --schedule   另外安装每日定时刷新 Claude 用量的任务（macOS：launchd；Linux：systemd 用户定时器）
# 可重复运行：已安装时更新脚本，不重复修改 ~/.zshrc，不覆盖已有的设置文件。
emulate -L zsh
set -e

src=${0:A:h}
dest=${ALB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/account-load-balancer}
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/account-load-balancer
zshrc=${ZDOTDIR:-$HOME}/.zshrc
schedule=0
[[ $1 == --schedule ]] && schedule=1

for cmd in jq curl perl; do
  whence -p $cmd >/dev/null || { print -u2 "缺少依赖：$cmd。请先安装后再运行。"; exit 1; }
done
whence -p claude >/dev/null || print -u2 '提示：未找到 claude 命令，cc0 / ccN 需要先安装 Claude Code。'
whence -p codex >/dev/null || print -u2 '提示：未找到 codex 命令，cx0 / cxN 需要先安装 Codex CLI。'

mkdir -p $dest $config_dir
cp $src/lib/*.zsh $dest/
chmod 755 $dest/*.zsh
print "脚本已安装到 $dest"

if [[ ! -f $config_dir/config.zsh ]]; then
  cp $src/templates/config.zsh $config_dir/config.zsh
  print "设置文件已创建：$config_dir/config.zsh"
else
  print "保留已有的设置文件：$config_dir/config.zsh"
fi

line="source ${dest/#$HOME/\$HOME}/alb.zsh   # account-load-balancer"
if grep -qF 'account-load-balancer' $zshrc 2>/dev/null; then
  print "$zshrc 中已有 source 行，未修改。"
else
  print "\n$line" >> $zshrc
  print "已在 $zshrc 末尾加入：$line"
fi

if (( schedule )); then
  if [[ $OSTYPE == darwin* ]]; then
    plist=$HOME/Library/LaunchAgents/account-load-balancer.cc-usage.plist
    sed -e "s#@ZSH@#$(whence -p zsh)#" -e "s#@SCRIPT@#$dest/cc-usage.zsh#" -e "s#@LOG@#${XDG_STATE_HOME:-$HOME/.local/state}/account-load-balancer/cc-usage.log#" \
      $src/templates/launchd.plist > $plist
    launchctl unload $plist 2>/dev/null || true
    launchctl load $plist
    print "已安装 launchd 定时任务：每天 09:30 刷新 Claude 用量（$plist）"
  else
    unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
    mkdir -p $unit_dir
    sed -e "s#@ZSH@#$(whence -p zsh)#" -e "s#@SCRIPT@#$dest/cc-usage.zsh#" $src/templates/cc-usage.service > $unit_dir/account-load-balancer-cc-usage.service
    cp $src/templates/cc-usage.timer $unit_dir/account-load-balancer-cc-usage.timer
    systemctl --user daemon-reload
    systemctl --user enable --now account-load-balancer-cc-usage.timer
    print "已安装 systemd 用户定时器：每天 09:30 刷新 Claude 用量"
  fi
fi

print "\n安装完成。新开一个终端，或运行 source $zshrc，然后按 README 的「登录账号」一节登录各账号。"
