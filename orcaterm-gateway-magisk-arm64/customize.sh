#!/system/bin/sh
# 安装/更新钩子：补权限
MODDIR="${0%/*}"
chmod 0755 "$MODDIR"/*.sh "$MODDIR/orcaterm-gateway" 2>/dev/null
exit 0
