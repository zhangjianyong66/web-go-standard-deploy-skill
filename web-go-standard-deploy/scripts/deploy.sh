#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-root@ecs1.zhangjianyong.top}"
RELEASE_ROOT="${RELEASE_ROOT:-/opt/web-projects-hub/releases}"
CURRENT_LINK="${CURRENT_LINK:-/opt/web-projects-hub/current/${APP_NAME:-}}"
NGINX_CONF="${NGINX_CONF:-/usr/local/nginx/conf/conf.d/${DOMAIN:-}.conf}"
RELEASE_ID="${RELEASE_ID:-$(date +%Y%m%d%H%M%S)}"
REMOTE_RELEASE_DIR="$RELEASE_ROOT/$APP_NAME/$RELEASE_ID"

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

echo "[INFO] release id: $RELEASE_ID"
ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_RELEASE_DIR/dist' '$REMOTE_RELEASE_DIR/bin'"

if [[ -f "./bin/server" ]]; then
  echo "[INFO] uploading backend binary ./bin/server"
  scp ./bin/server "$REMOTE_HOST:$REMOTE_RELEASE_DIR/bin/server"
  ssh "$REMOTE_HOST" "chmod +x '$REMOTE_RELEASE_DIR/bin/server'"
else
  echo "[WARN] ./bin/server not found locally, skip backend binary upload"
fi

echo "[INFO] uploading frontend dist"
scp -r "$FRONTEND_DIST"/* "$REMOTE_HOST:$REMOTE_RELEASE_DIR/dist/"

echo "[INFO] switching symlinks and restarting service"
ssh "$REMOTE_HOST" "
  set -e
  APP_ROOT='$RELEASE_ROOT/$APP_NAME'
  PREVIOUS_LINK=\"$APP_ROOT/previous\"

  if [ -L '$CURRENT_LINK' ]; then
    CUR_TARGET=\$(readlink -f '$CURRENT_LINK' || true)
    if [ -n \"\$CUR_TARGET\" ]; then
      ln -sfn \"\$CUR_TARGET\" \"\$PREVIOUS_LINK\"
    fi
  fi

  ln -sfn '$REMOTE_RELEASE_DIR' '$CURRENT_LINK'
  systemctl restart '$GO_SERVICE'
  sleep 2
  curl -fsS '$GO_HEALTH_URL' >/dev/null

  nginx -t
  systemctl reload nginx || nginx -s reload
"

echo "[INFO] verifying domain"
curl -k -I --max-time 10 "https://$DOMAIN" | head -n 1

echo "[OK] deploy finished: $REMOTE_RELEASE_DIR"
