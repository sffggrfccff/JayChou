#!/system/bin/sh
# Magisk 模块「操作」按钮 → 打开 OrcaTerm 网关管理面板
MODDIR="${MODDIR:-${0%/*}}"
DATA="/data/adb/orcaterm-gateway"
PIDF="$DATA/gateway.pid"
PORT=8890

if ! { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }; then
    echo "服务未运行，正在启动..."
    sh "$MODDIR/service.sh" start >/dev/null 2>&1
    sleep 1
fi

LOCAL="http://127.0.0.1:$PORT/"
LANIP="$(ip -4 addr show wlan0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)"
[ -n "$LANIP" ] || LANIP="$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | head -1)"

echo "OrcaTerm 网关 管理面板"
echo "  本机：$LOCAL"
[ -n "$LANIP" ] && echo "  局域网：http://$LANIP:$PORT/"
echo "  密码：password"

if am start -a android.intent.action.VIEW -d "$LOCAL" >/dev/null 2>&1; then
    echo "已调起浏览器打开管理面板"
else
    echo "未能自动打开浏览器，请手动访问上面的地址"
fi
