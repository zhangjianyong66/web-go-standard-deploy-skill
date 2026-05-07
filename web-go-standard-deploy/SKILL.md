---
name: web-go-standard-deploy
description: Deploy Vue static files to ecs1 Nginx and route /api to local Mac Go service through FRP, with precheck, postcheck, and rollback guardrails.
---

# Web + Go Hybrid Deploy (ecs1 + Mac via FRP)

## Overview
This skill supports two modes:
- `MODE=frp-hybrid` (default): frontend on ecs1, Go API on local Mac, ecs1 Nginx proxies `/api` to FRP mapped port.
- `MODE=remote-full`: legacy mode where frontend + Go both run on ecs1.

Default policy: **precheck first, then switch, then postcheck**.

## Environment Facts (confirmed 2026-05-07)
- Remote host: `root@ecs1.zhangjianyong.top`
- ECS1 OS: CentOS 8
- Nginx config root: `/usr/local/nginx/conf/conf.d`
- FRPS on ecs1: `/etc/frp/frps.ini` (`bind_port=7000`) with `frps.service`
- SSL renew: `/root/ssl_auto_renew/ssl_auto_renew.sh` + root `crontab`
- Local Mac currently needs `frpc` installed for `frp-hybrid`

## Required Inputs
Common:
- `APP_NAME`
- `DOMAIN`
- `FRONTEND_DIST`

Common optional:
- `MODE` default `frp-hybrid`
- `REMOTE_HOST` default `root@ecs1.zhangjianyong.top`
- `RELEASE_ROOT` default `/opt/web-projects-hub/releases`
- `CURRENT_LINK` default `/opt/web-projects-hub/current/$APP_NAME`
- `NGINX_CONF` default `/usr/local/nginx/conf/conf.d/$DOMAIN.conf`
- `API_PREFIX` default `/api`

For `MODE=frp-hybrid`:
- `LOCAL_GO_HEALTH_URL` (example: `http://127.0.0.1:18080/health`)
- `LOCAL_GO_PORT` (example: `18080`)
- `FRP_SERVER_ADDR` default `ecs1.zhangjianyong.top`
- `FRP_SERVER_PORT` default `7000`
- `FRP_TOKEN` (must be injected from secret env)
- `FRP_REMOTE_PORT` default `17080`

For `MODE=remote-full`:
- `GO_SERVICE`
- `GO_HEALTH_URL`

## Nginx Requirements (`frp-hybrid`)
In `$NGINX_CONF`, include API reverse proxy:

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:17080/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

If `API_PREFIX` is changed, make Nginx location match it.

## FRP Startup on Mac (`frp-hybrid`)
Use bundled helper:

```bash
export APP_NAME="myapp"
export FRP_SERVER_ADDR="ecs1.zhangjianyong.top"
export FRP_SERVER_PORT="7000"
export FRP_TOKEN="<secret>"
export LOCAL_GO_PORT="18080"
export FRP_REMOTE_PORT="17080"

./scripts/frp/run-frpc.sh
```

## Standard Flow
1. `./scripts/precheck.sh`
2. Build frontend locally (`npm run build`)
3. `./scripts/deploy.sh`
4. `./scripts/postcheck.sh`
5. If failed: `./scripts/rollback.sh`

## Command Example (`frp-hybrid`, recommended)
```bash
export MODE="frp-hybrid"
export APP_NAME="storieshub"
export DOMAIN="storieshub.zhangjianyong.top"
export FRONTEND_DIST="./dist"
export LOCAL_GO_HEALTH_URL="http://127.0.0.1:18080/health"
export LOCAL_GO_PORT="18080"
export FRP_SERVER_ADDR="ecs1.zhangjianyong.top"
export FRP_SERVER_PORT="7000"
export FRP_TOKEN="<secret>"
export FRP_REMOTE_PORT="17080"
export API_PREFIX="/api"

./scripts/frp/run-frpc.sh
./scripts/precheck.sh
./scripts/deploy.sh
./scripts/postcheck.sh
```

## Guardrails
- Never reload nginx before `nginx -t` passes.
- Never store `FRP_TOKEN` in repo files.
- Keep Go API binding on Mac at `127.0.0.1`.
- Keep previous release symlink for rollback.

## Acceptance Criteria
- `https://$DOMAIN` returns expected site response.
- `https://$DOMAIN$API_PREFIX/health` is healthy.
- `nginx -t` passes and reload succeeds.
- SSL renew script and cron entries remain valid.
- (`remote-full` only) `systemctl is-active $GO_SERVICE` is `active`.
