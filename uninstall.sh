#!/bin/zsh
# 卸载 account-load-balancer：删除脚本、定时任务和 ~/.zshrc 中的 source 行。
# 不删除设置文件、用量缓存，也不删除各账号的配置目录和登录信息。
emulate -L zsh
dest=${ALB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/account-load-balancer}
zshrc=${ZDOTDIR:-$HOME}/.zshrc

if [[ $OSTYPE == darwin* ]]; then
  plist=$HOME/Library/LaunchAgents/account-load-balancer.cc-usage.plist
  [[ -f $plist ]] && { launchctl unload $plist 2>/dev/null; rm -f $plist; print "已删除定时任务 $plist"; }
elif systemctl --user list-unit-files 2>/dev/null | grep -q account-load-balancer-cc-usage; then
  systemctl --user disable --now account-load-balancer-cc-usage.timer
  rm -f ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/account-load-balancer-cc-usage.{service,timer}
  systemctl --user daemon-reload
  print '已删除 systemd 用户定时器'
fi

if grep -qF '# account-load-balancer' $zshrc 2>/dev/null; then
  cp $zshrc $zshrc.bak-alb
  grep -vF '# account-load-balancer' $zshrc.bak-alb > $zshrc
  print "已从 $zshrc 删除 source 行（原文件备份为 $zshrc.bak-alb）"
fi

rm -rf $dest && print "已删除 $dest"
print '设置文件、用量缓存和各账号的登录信息均已保留。'
