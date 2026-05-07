#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-root@ecs1.zhangjianyong.top}"
RELEASE_ROOT="${RELEASE_ROOT:-/opt/web-projects-hub/releases}"
CURRENT_LINK="${CURRENT_LINK:-/opt/web-projects-hub/current/${APP_NAME:-}}"
NGINX_CONF="${NGINX_CONF:-/usr/local/nginx/conf/conf.d/${DOMAIN:-}.conf}"

required_vars=(APP_NAME DOMAIN FRONTEND_DIST GO_SERVICE GO_HEALTH_URL)
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

echo "[INFO] checking remote service and nginx"
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

echo "[OK] precheck passed"
