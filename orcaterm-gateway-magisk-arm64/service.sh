#!/system/bin/sh
# OrcaTerm 网关 — Magisk / KernelSU / APatch 模块服务脚本
# 手动控制（root）:
#   sh /data/adb/modules/orcaterm-gateway/service.sh start|stop|restart|status|logs
MODDIR="${MODDIR:-${0%/*}}"
BIN="$MODDIR/orcaterm-gateway"
DATA="/data/adb/orcaterm-gateway"
PIDF="$DATA/gateway.pid"
LOGF="$DATA/gateway.log"
BOOTLOG="$DATA/boot.log"

LISTEN="0.0.0.0:8890"
HP="${LISTEN##*:}"
# 管理面板访问密码（不要鉴权请留空）
export ORCA_ADMIN_PASSWORD="password"
export ORCA_DATA_DIR="$DATA"
TZ="Asia/Shanghai"

DNS="$(getprop net.dns1 2>/dev/null)"
[ -n "$DNS" ] || DNS="$(getprop net.dns2 2>/dev/null)"
[ -n "$DNS" ] || DNS="223.5.5.5"
export SSL_CERT_DIR="/system/etc/security/cacerts"

blog() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$$] $*" >> "$BOOTLOG" 2>/dev/null; }

running_pid() {
    [ -f "$PIDF" ] || return 1
    _p="$(cat "$PIDF" 2>/dev/null)"
    [ -n "$_p" ] || return 1
    kill -0 "$_p" 2>/dev/null || return 1
    _c="$(cat "/proc/$_p/cmdline" 2>/dev/null | tr -d '\000')"
    case "$_c" in *orcaterm-gateway*) echo "$_p"; return 0 ;; esac
    return 1
}

health_code() {
    curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$HP/health" 2>/dev/null
}

start() {
    _rp="$(running_pid)"
    if [ -n "$_rp" ]; then echo "orcaterm-gateway: already running (pid $_rp)"; return 0; fi
    rm -f "$PIDF"
    chmod 0755 "$BIN" 2>/dev/null
    mkdir -p "$DATA"
    cd "$DATA" || return 1
    "$BIN" >> "$LOGF" 2>&1 </dev/null &
    _np="$!"
    echo "$_np" > "$PIDF"
    _n=0
    while [ "$_n" -lt 20 ]; do
        sleep 1; _n=$((_n+1))
        [ "$(health_code)" = "200" ] && break
        kill -0 "$_np" 2>/dev/null || break
    done
    if [ "$(health_code)" = "200" ]; then
        echo "orcaterm-gateway: started (pid $_np, http://$LISTEN)"
        return 0
    fi
    echo "orcaterm-gateway: 启动失败"; tail -5 "$LOGF" 2>/dev/null; return 1
}

stop() {
    _rp="$(running_pid)"
    if [ -n "$_rp" ]; then kill "$_rp" 2>/dev/null; sleep 1; kill -9 "$_rp" 2>/dev/null; echo "stopped (pid $_rp)"; fi
    rm -f "$PIDF"
}

case "${1:-}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; start ;;
    status)  _rp="$(running_pid)"; [ -n "$_rp" ] && echo "RUNNING pid=$_rp health=$(health_code)" || echo "DOWN" ;;
    logs)    tail -n "${2:-50}" "$LOGF" 2>/dev/null ;;
    "")      start ;;
    *)       echo "usage: $0 {start|stop|restart|status|logs}"; exit 1 ;;
esac
