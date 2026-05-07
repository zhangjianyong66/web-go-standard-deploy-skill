#!/usr/bin/env bash
set -euo pipefail

: "${APP_NAME:?missing APP_NAME}"
: "${FRP_SERVER_ADDR:=ecs1.zhangjianyong.top}"
: "${FRP_SERVER_PORT:=7000}"
: "${FRP_TOKEN:?missing FRP_TOKEN}"
: "${LOCAL_GO_PORT:?missing LOCAL_GO_PORT}"
: "${FRP_REMOTE_PORT:=17080}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="${script_dir}/.work"
mkdir -p "$work_dir"

export APP_NAME FRP_SERVER_ADDR FRP_SERVER_PORT FRP_TOKEN LOCAL_GO_PORT FRP_REMOTE_PORT
envsubst < "${script_dir}/frpc.template.toml" > "${work_dir}/frpc.toml"

if pgrep -f "frpc -c ${work_dir}/frpc.toml" >/dev/null 2>&1; then
  echo "[INFO] frpc already running with ${work_dir}/frpc.toml"
  exit 0
fi

nohup frpc -c "${work_dir}/frpc.toml" > "${work_dir}/frpc.log" 2>&1 &
sleep 1
pgrep -f "frpc -c ${work_dir}/frpc.toml" >/dev/null 2>&1 || {
  echo "[ERROR] frpc failed to start; check ${work_dir}/frpc.log" >&2
  exit 1
}

echo "[OK] frpc started"
