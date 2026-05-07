#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-root@ecs1.zhangjianyong.top}"
RELEASE_ROOT="${RELEASE_ROOT:-/opt/web-projects-hub/releases}"
CURRENT_LINK="${CURRENT_LINK:-/opt/web-projects-hub/current/${APP_NAME:-}}"

required_vars=(APP_NAME GO_SERVICE GO_HEALTH_URL)
for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "[ERROR] missing env var: $v" >&2
    exit 1
  fi
done

ssh "$REMOTE_HOST" "
  set -e
  APP_ROOT='$RELEASE_ROOT/$APP_NAME'
  PREVIOUS_LINK=\"$APP_ROOT/previous\"

  test -L \"\$PREVIOUS_LINK\" || { echo '[ERROR] previous release link not found'; exit 1; }
  PREV_TARGET=\$(readlink -f \"\$PREVIOUS_LINK\")
  test -d \"\$PREV_TARGET\" || { echo '[ERROR] previous target missing'; exit 1; }

  ln -sfn \"\$PREV_TARGET\" '$CURRENT_LINK'
  systemctl restart '$GO_SERVICE'
  sleep 2
  curl -fsS '$GO_HEALTH_URL' >/dev/null

  nginx -t
  systemctl reload nginx || nginx -s reload
"

echo "[OK] rollback finished"
