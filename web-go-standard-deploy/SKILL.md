---
name: web-go-standard-deploy
description: Use when deploying a web project with static frontend + Go backend on ecs1, with Nginx reverse proxy and SSL auto-renew checks, requiring precheck-gated rollout and rollback safety.
---

# Web + Go Standard Deploy (ecs1)

## Overview
This skill standardizes deployment for mixed projects (frontend static files + Go API) on `root@ecs1.zhangjianyong.top`.

Default policy: **verify first, then switch**, with explicit rollback checkpoints.

## Environment Facts (locked)
- SSH: passwordless access is available for `root@ecs1.zhangjianyong.top`
- OS: CentOS 8
- Nginx active config root: `/usr/local/nginx/conf/conf.d`
- Go process management: prefer `systemd` services (for example `blog-go.service`)
- SSL renew mechanism: `/root/ssl_auto_renew/ssl_auto_renew.sh` + root `crontab`

## Required Inputs
Set these variables before running scripts:

- `APP_NAME`: logical app name, e.g. `storieshub`
- `DOMAIN`: external domain, e.g. `storieshub.zhangjianyong.top`
- `FRONTEND_DIST`: local built frontend directory
- `GO_SERVICE`: systemd service name, e.g. `blog-go.service`
- `GO_HEALTH_URL`: backend health endpoint, e.g. `http://127.0.0.1:18080/health`

Optional:
- `REMOTE_HOST` default: `root@ecs1.zhangjianyong.top`
- `RELEASE_ROOT` default: `/opt/web-projects-hub/releases`
- `CURRENT_LINK` default: `/opt/web-projects-hub/current/$APP_NAME`
- `NGINX_CONF` default: `/usr/local/nginx/conf/conf.d/$DOMAIN.conf`
- `BACKEND_PORT`: for port checks

## Standard Flow
1. Precheck (`scripts/precheck.sh`)
- Validate SSH connectivity
- Validate required vars
- Validate `systemctl` service existence
- Validate nginx config file existence and syntax (`nginx -t`)
- Validate SSL renew job and script presence
- Validate host disk usage

2. Build & Package
- Build frontend locally (`npm run build` or project equivalent)
- Build Go binary locally or in CI
- Ensure artifacts are versioned by release id (timestamp)

3. Upload to release directory
- Target: `$RELEASE_ROOT/$APP_NAME/$RELEASE_ID`
- Upload frontend assets to `dist/`
- Upload backend binary to `bin/`

4. Switch with checks (`scripts/deploy.sh`)
- Create/update `previous` symlink from current
- Atomically switch `current` symlink to new release
- Run `systemctl restart $GO_SERVICE`
- Run backend health check
- Run `nginx -t` then reload nginx
- Run HTTP check on `https://$DOMAIN`

5. Postcheck (`scripts/postcheck.sh`)
- Confirm service is active
- Confirm endpoint healthy
- Confirm TLS cert remaining days above threshold
- Confirm ssl auto-renew cron entries still present

6. Rollback (`scripts/rollback.sh`) when any check fails
- Switch `current` back to `previous`
- Restart go service
- Reload nginx
- Re-run health checks

## Guardrails
- Never reload nginx before passing `nginx -t`
- Never delete prior release until new release passes health checks
- Any failure in deploy script must stop immediately (`set -euo pipefail`)

## Command Examples
```bash
export APP_NAME="storieshub"
export DOMAIN="storieshub.zhangjianyong.top"
export FRONTEND_DIST="./dist"
export GO_SERVICE="blog-go.service"
export GO_HEALTH_URL="http://127.0.0.1:18080/health"
export REMOTE_HOST="root@ecs1.zhangjianyong.top"

./scripts/precheck.sh
./scripts/deploy.sh
./scripts/postcheck.sh
```

Rollback:
```bash
./scripts/rollback.sh
```

## Acceptance Criteria
- `systemctl is-active $GO_SERVICE` returns `active`
- `curl $GO_HEALTH_URL` returns success
- `curl -I https://$DOMAIN` returns 200/301/302 as expected
- `nginx -t` passes and nginx reload succeeds
- SSL renew script and cron entries remain valid
