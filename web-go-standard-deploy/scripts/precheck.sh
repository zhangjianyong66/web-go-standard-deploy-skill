#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-frp-hybrid}"
REMOTE_HOST="${REMOTE_HOST:-root@ecs1.zhangjianyong.top}"
RELEASE_ROOT="${RELEASE_ROOT:-/opt/web-projects-hub/releases}"
CURRENT_LINK="${CURRENT_LINK:-/opt/web-projects-hub/current/${APP_NAME:-}}"
NGINX_CONF="${NGINX_CONF:-/usr/local/nginx/conf/conf.d/${DOMAIN:-}.conf}"
API_PREFIX="${API_PREFIX:-/api}"
FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-ecs1.zhangjianyong.top}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_REMOTE_PORT="${FRP_REMOTE_PORT:-17080}"

required_vars=(APP_NAME DOMAIN FRONTEND_DIST)
for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "[ERROR] missing env var: $v" >&2
    exit 1
  fi
done

if [[ ! -d "$FRONTEND_DIST" ]]; then
  echo "[ERROR] FRONTEND_DIST not found: $FRONTEND_DIST" >&2
  exit 1
fi

echo "[INFO] checking SSH: $REMOTE_HOST"
ssh -o BatchMode=yes -o ConnectTimeout=8 "$REMOTE_HOST" 'echo ok >/dev/null'

case "$MODE" in
  remote-full)
    mode_vars=(GO_SERVICE GO_HEALTH_URL)
    for v in "${mode_vars[@]}"; do
      if [[ -z "${!v:-}" ]]; then
        echo "[ERROR] missing env var: $v" >&2
        exit 1
      fi
    done
    echo "[INFO] checking remote service and nginx (remote-full)"
    ssh "$REMOTE_HOST" "
      set -e
      systemctl status '$GO_SERVICE' >/dev/null 2>&1 || { echo '[ERROR] service not found: $GO_SERVICE'; exit 1; }
      test -f '$NGINX_CONF' || { echo '[ERROR] nginx conf missing: $NGINX_CONF'; exit 1; }
      nginx -t
      test -x /root/ssl_auto_renew/ssl_auto_renew.sh || { echo '[ERROR] ssl_auto_renew script missing'; exit 1; }
      crontab -l | grep -q '/root/ssl_auto_renew/ssl_auto_renew.sh' || { echo '[ERROR] ssl_auto_renew cron missing'; exit 1; }
      df -h /
      mkdir -p '$RELEASE_ROOT/$APP_NAME'
      mkdir -p '$(dirname "$CURRENT_LINK")'
    "
    ;;
  frp-hybrid)
    mode_vars=(LOCAL_GO_HEALTH_URL FRP_TOKEN)
    for v in "${mode_vars[@]}"; do
      if [[ -z "${!v:-}" ]]; then
        echo "[ERROR] missing env var: $v" >&2
        exit 1
      fi
    done
    command -v frpc >/dev/null 2>&1 || { echo "[ERROR] frpc not found on local Mac"; exit 1; }
    curl -fsS "$LOCAL_GO_HEALTH_URL" >/dev/null || { echo "[ERROR] local go health check failed: $LOCAL_GO_HEALTH_URL"; exit 1; }

    echo "[INFO] checking remote nginx, ssl cron and FRP port (frp-hybrid)"
    ssh "$REMOTE_HOST" "
      set -e
      test -f '$NGINX_CONF' || { echo '[ERROR] nginx conf missing: $NGINX_CONF'; exit 1; }
      nginx -t
      test -x /root/ssl_auto_renew/ssl_auto_renew.sh || { echo '[ERROR] ssl_auto_renew script missing'; exit 1; }
      crontab -l | grep -q '/root/ssl_auto_renew/ssl_auto_renew.sh' || { echo '[ERROR] ssl_auto_renew cron missing'; exit 1; }
      grep -q 'location $API_PREFIX/' '$NGINX_CONF' || { echo '[ERROR] nginx missing API_PREFIX location: $API_PREFIX/'; exit 1; }
      ss -lnt | awk '{print \$4}' | grep -q ':$FRP_REMOTE_PORT$' && { echo '[ERROR] FRP_REMOTE_PORT already in use: $FRP_REMOTE_PORT'; exit 1; } || true
      mkdir -p '$RELEASE_ROOT/$APP_NAME'
      mkdir -p '$(dirname "$CURRENT_LINK")'
    "
    ;;
  *)
    echo "[ERROR] invalid MODE: $MODE (expected: frp-hybrid or remote-full)" >&2
    exit 1
    ;;
esac

echo "[OK] precheck passed"
