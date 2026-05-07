#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-root@ecs1.zhangjianyong.top}"
MIN_CERT_DAYS="${MIN_CERT_DAYS:-7}"

required_vars=(DOMAIN GO_SERVICE GO_HEALTH_URL)
for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "[ERROR] missing env var: $v" >&2
    exit 1
  fi
done

ssh "$REMOTE_HOST" "
  set -e
  systemctl is-active '$GO_SERVICE' | grep -q active
  curl -fsS '$GO_HEALTH_URL' >/dev/null
  crontab -l | grep -q '/root/ssl_auto_renew/ssl_auto_renew.sh'
"

curl -k -fsSI --max-time 10 "https://$DOMAIN" >/dev/null

cert_end=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
if [[ -z "$cert_end" ]]; then
  echo "[ERROR] cannot parse cert end date for $DOMAIN" >&2
  exit 1
fi

end_ts=$(date -d "$cert_end" +%s)
now_ts=$(date +%s)
left_days=$(( (end_ts - now_ts) / 86400 ))

echo "[INFO] cert days left: $left_days"
if (( left_days < MIN_CERT_DAYS )); then
  echo "[ERROR] cert remaining days ($left_days) < threshold ($MIN_CERT_DAYS)" >&2
  exit 1
fi

echo "[OK] postcheck passed"
