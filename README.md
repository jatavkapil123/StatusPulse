# StatusPulse

A lightweight service status and incident tracking API built with FastAPI, PostgreSQL, and Redis.

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │              Server / VM                 │
                        │                                          │
  Internet              │  ┌──────────┐     ┌───────────────────┐ │
  ──────────── HTTPS ──►│  │  Caddy   │────►│   FastAPI (api)   │ │
                        │  │ (TLS/RP) │     │   :8000           │ │
                        │  └──────────┘     └────────┬──────────┘ │
                        │                            │            │
                        │              ┌─────────────┴──────────┐ │
                        │              │                        │ │
                        │       ┌──────▼──────┐   ┌────────────▼┐│
                        │       │ PostgreSQL  │   │    Redis    ││
                        │       │   :5432     │   │    :6379    ││
                        │       └─────────────┘   └─────────────┘│
                        │                                          │
                        │  ┌──────────────────────────────────┐   │
                        │  │  Uptime Kuma  :3001              │   │
                        │  └──────────────────────────────────┘   │
                        └─────────────────────────────────────────┘

  CI/CD: GitHub Actions → ghcr.io → SSH deploy → health check → rollback
```

## Prerequisites

- Docker + Docker Compose
- `make`
- `curl`, `python3` (for tests)

## Run Locally with Docker Compose

```bash
# 1. Clone the repo
git clone https://github.com/your-org/statuspulse
cd statuspulse

# 2. Create .env from example
cp .env.example .env
# Edit .env and set strong passwords

# 3. Build and start
make build
make up

# 4. Verify
make test
# → curl http://localhost:8000/health
```

API docs: http://localhost:8000/docs

## Makefile Targets

| Target       | Description                                      |
|--------------|--------------------------------------------------|
| `make build` | Build the Docker image                           |
| `make up`    | Start all services (detached)                    |
| `make down`  | Stop all services                                |
| `make logs`  | Tail API logs                                    |
| `make test`  | Health check via curl                            |
| `make clean` | Remove containers, images, and volumes           |
| `make shell` | Open bash inside the running api container       |

## Deploy to Production

### Prerequisites
- A server provisioned via Terraform on Azure (see `terraform/`)
- Domain pointing to server IP (optional)
- GitHub Secrets configured (see CI/CD section)

```bash
# Provision server
cd terraform
terraform init
terraform apply -var="admin_password=YourStr0ng!Pass"

# Get the server IP
terraform output server_ip
```

The VM bootstraps itself automatically — Docker, firewall, swap, cron jobs, and Uptime Kuma are all installed on first boot. Push to `main` to trigger the deploy pipeline.

## CI/CD Pipeline

### CI (`.github/workflows/ci.yml`)
Runs on every push and PR to `main`:
1. Lint Python with `ruff`
2. Scan `Dockerfile` with `hadolint`
3. Build Docker image
4. Start full stack via Docker Compose
5. Run `tests/test_integration.sh` against live stack
6. Tear down stack
7. Upload test results as artifact

### Deploy (`.github/workflows/deploy.yml`)
Runs on push to `main` after CI passes:
1. Build and push image to `ghcr.io` (tagged with commit SHA + `latest`)
2. SSH into server and run `scripts/deploy.sh`
3. Post-deployment health check
4. Auto-rollback if health check fails
5. GitHub Issue comment notification on success/failure

### Required GitHub Secrets

| Secret            | Description                        |
|-------------------|------------------------------------|
| `DEPLOY_HOST`     | Server hostname or IP              |
| `DEPLOY_USER`     | SSH user (e.g. `deploy`)           |
| `DEPLOY_SSH_KEY`  | Private SSH key                    |
| `DEPLOY_SSH_PORT` | SSH port (e.g. `2222`)             |

## Monitoring & Alerting

### Uptime Kuma
Running at `https://status.<your-domain>/`. Monitors:
- StatusPulse `/health` (every 60s)
- PostgreSQL TCP :5432
- Redis TCP :6379
- TLS certificate expiry

### Health Monitor Cron
```bash
# /etc/cron.d/statuspulse-monitor
*/5 * * * * deploy /opt/statuspulse/scripts/health-monitor.sh
```
Checks: HTTP health, disk >80%, memory >90%, container status, TLS expiry <14 days.
Alerts via `$ALERT_WEBHOOK_URL`.

Logs: `/var/log/statuspulse-monitor.log`

## Backup & Restore

### Backup
```bash
# Manual
bash scripts/backup.sh

# Automated (daily at 2am)
# 0 2 * * * /opt/statuspulse/scripts/backup.sh
```
Backups saved to `/opt/statuspulse/backups/`, last 7 kept. Optional S3 upload via `$S3_BUCKET`.

### Restore
```bash
# Decompress and restore to running db container
gunzip -c backups/statuspulse_db_2024-01-01_020000.sql.gz \
  | docker compose exec -T db psql -U statuspulse statuspulse
```

## Troubleshooting

**Services not starting**
```bash
docker compose ps        # check status
docker compose logs db   # check postgres logs
docker compose logs api  # check api logs
```

**Health check failing**
```bash
curl http://localhost:8000/health
# Check DB_HOST, DB_USER, DB_PASSWORD in .env
```

**Port already in use**
```bash
# Change APP_PORT in .env, then make down && make up
```

**Out of disk space**
```bash
docker system prune -f   # remove unused images/containers
bash scripts/backup.sh   # ensure old backups are rotated
```
