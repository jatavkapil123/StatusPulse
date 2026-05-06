# StatusPulse — Full Project Documentation

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Tech Stack](#3-tech-stack)
4. [Repository Structure](#4-repository-structure)
5. [Application — FastAPI Service](#5-application--fastapi-service)
6. [Docker & Containerization](#6-docker--containerization)
7. [Infrastructure — Terraform on AWS](#7-infrastructure--terraform-on-aws)
8. [CI Pipeline](#8-ci-pipeline)
9. [CD Pipeline & Zero-Downtime Deploy](#9-cd-pipeline--zero-downtime-deploy)
10. [Deployment Walkthrough (Screenshots)](#10-deployment-walkthrough-screenshots)
11. [Monitoring & Alerting](#11-monitoring--alerting)
12. [Backup & Restore](#12-backup--restore)
13. [Environment Variables Reference](#13-environment-variables-reference)
14. [Makefile Reference](#14-makefile-reference)
15. [Security](#15-security)
16. [Troubleshooting](#16-troubleshooting)

---

## 1. Project Overview

**StatusPulse** is a lightweight service status and incident tracking API. It lets you register services, track their health, and log incidents — all through a clean REST API backed by PostgreSQL and Redis.

Key capabilities:
- REST API built with FastAPI (Python 3.11)
- PostgreSQL for persistent storage of services and incidents
- Redis for real-time incident pub/sub
- Caddy as a reverse proxy with automatic HTTPS via Let's Encrypt
- Full CI/CD via GitHub Actions with zero-downtime deploys and automatic rollback
- Infrastructure provisioned on AWS EC2 via Terraform

---

## 2. Architecture

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
                        └─────────────────────────────────────────┘

  CI/CD: GitHub Actions → ghcr.io → SSH deploy → health check → rollback
```

**Request flow:**
1. Client sends HTTPS request to the domain
2. Caddy terminates TLS and reverse-proxies to the FastAPI container on port 8000
3. FastAPI reads/writes to PostgreSQL for persistent data
4. FastAPI publishes incident events to Redis pub/sub channel
5. Health checks hit `/health` which probes both DB and Redis connectivity

---

## 3. Tech Stack

| Layer | Technology | Version |
|---|---|---|
| API Framework | FastAPI | 0.104.1 |
| ASGI Server | Uvicorn | 0.24.0 |
| Production Server | Gunicorn | 21.2.0 |
| Database | PostgreSQL | 15-alpine |
| Cache / Pub-Sub | Redis | 7-alpine |
| Reverse Proxy | Caddy | latest |
| Container Runtime | Docker + Compose | v3.9 |
| Infrastructure | Terraform + AWS EC2 | ~5.0 |
| CI/CD | GitHub Actions | — |
| Image Registry | GitHub Container Registry (ghcr.io) | — |
| Language | Python | 3.11 |

---

## 4. Repository Structure

```
statuspulse/
├── app/
│   ├── main.py              # FastAPI application
│   └── requirements.txt     # Python dependencies
├── caddy/
│   └── Caddyfile            # Reverse proxy + TLS config
├── scripts/
│   ├── deploy.sh            # Zero-downtime deploy + rollback
│   ├── backup.sh            # PostgreSQL backup with rotation
│   └── health-monitor.sh    # Cron-based health monitor + alerting
├── terraform/
│   ├── main.tf              # EC2 + Security Group + Elastic IP
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Server IP + SSH command
│   └── userdata.sh.tpl      # Server bootstrap script
├── tests/
│   └── test_integration.sh  # Integration test suite
├── .github/
│   └── workflows/
│       ├── ci.yml           # Lint → Build → Test pipeline
│       └── deploy.yml       # Build → Push → Deploy pipeline
├── photo/                   # Screenshots used in this documentation
├── Dockerfile               # Multi-stage Docker build
├── docker-compose.yml       # Local + production service definitions
├── Makefile                 # Developer shortcuts
├── .env.example             # Environment variable template
└── SECURITY.md              # Security policy
```

---

## 5. Application — FastAPI Service

The core application lives in `app/main.py`. It exposes five endpoints:

### Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | Service info and links |
| `GET` | `/health` | Health check — probes DB and Redis |
| `POST` | `/services` | Register a new service to monitor |
| `GET` | `/services` | List all registered services |
| `POST` | `/incidents` | Create an incident |
| `GET` | `/incidents` | List all incidents (newest first) |

### `/health` Response

```json
{
  "status": "healthy",
  "checks": {
    "api": "healthy",
    "database": "healthy",
    "redis": "healthy"
  },
  "timestamp": "2026-05-06T14:00:00+00:00"
}
```

`status` is `healthy` only when all three checks pass. Otherwise it returns `degraded`.

### Database Schema

**services**
```sql
CREATE TABLE services (
    id               SERIAL PRIMARY KEY,
    name             VARCHAR(100) UNIQUE NOT NULL,
    url              VARCHAR(500) NOT NULL,
    status           VARCHAR(20) DEFAULT 'unknown',
    last_checked     TIMESTAMP,
    response_time_ms INTEGER
);
```

**incidents**
```sql
CREATE TABLE incidents (
    id           SERIAL PRIMARY KEY,
    service_name VARCHAR(100) NOT NULL,
    title        VARCHAR(200) NOT NULL,
    description  TEXT,
    severity     VARCHAR(20) DEFAULT 'minor',
    status       VARCHAR(20) DEFAULT 'investigating',
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at  TIMESTAMP
);
```

Tables are created automatically on startup via `init_db()`.

### Redis Pub/Sub

When an incident is created, the API publishes a JSON message to the `incidents` channel:

```json
{ "id": 1, "title": "DB latency spike", "severity": "major" }
```

This allows downstream consumers (dashboards, alerting systems) to react in real time.

---

## 6. Docker & Containerization

### Multi-Stage Dockerfile

The build uses two stages to keep the final image small and secure:

```
Stage 1 (builder): python:3.11-slim
  └── pip install --prefix=/install -r requirements.txt

Stage 2 (runtime): python:3.11-slim
  ├── Non-root user: appuser / appgroup
  ├── Copy /install from builder
  ├── Copy app/main.py
  └── CMD: uvicorn main:app --host 0.0.0.0 --port 8000
```

The app runs as a non-root user (`appuser`) and has a built-in `HEALTHCHECK` that polls `/health` every 30 seconds.

### Docker Compose Services

```
statuspulse_net (bridge network)
├── db       — postgres:15-alpine  (256MB limit, healthcheck: pg_isready)
├── redis    — redis:7-alpine      (128MB limit, healthcheck: redis-cli ping)
└── api      — built from .        (256MB limit, depends on db + redis healthy)
```

The `api` service only starts after both `db` and `redis` pass their healthchecks (`condition: service_healthy`).

### Running Locally

```bash
cp .env.example .env
# Edit .env — set DB_PASSWORD at minimum

make build    # docker compose build
make up       # docker compose up -d
make test     # curl http://localhost:8000/health
```

API docs available at: `http://localhost:8000/docs`

---

## 7. Infrastructure — Terraform on AWS

The `terraform/` directory provisions a production-ready EC2 instance.

### Resources Created

| Resource | Details |
|---|---|
| `aws_security_group` | Allows custom SSH port, 80, 443. Denies all other inbound. |
| `aws_instance` | Ubuntu 22.04, t3.micro, 20GB gp3, bootstrapped via userdata |
| `aws_eip` | Static Elastic IP attached to the instance |

### Server Bootstrap (`userdata.sh.tpl`)

On first boot the server automatically:
1. Creates a non-root `deploy` user
2. Hardens SSH — custom port, no root login, no password auth
3. Configures UFW firewall (deny inbound by default, allow SSH/80/443)
4. Installs Docker CE + docker-compose-plugin
5. Creates 1GB swap file
6. Enables unattended security upgrades
7. Creates `/opt/statuspulse` owned by the deploy user

### Provisioning

```bash
cd terraform
terraform init
terraform apply -var="key_name=your-ec2-keypair"
```

Outputs:
```
server_ip   = "x.x.x.x"
ssh_command = "ssh -p 2222 deploy@x.x.x.x"
```

### Variables

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `ami` | Ubuntu 22.04 (us-east-1) | AMI ID |
| `instance_type` | `t3.micro` | EC2 instance type |
| `key_name` | required | EC2 key pair name |
| `ssh_port` | `2222` | Hardened SSH port |
| `deploy_user` | `deploy` | Non-root deploy user |

---

## 8. CI Pipeline

**File:** `.github/workflows/ci.yml`  
**Triggers:** Push or PR to `main`

### Steps

```
1. Checkout code
2. Set up Python 3.11
3. Install ruff (linter)
4. Lint app/main.py with ruff
5. Scan Dockerfile with hadolint (fails on errors)
6. Copy .env.example → .env
7. docker compose build
8. docker compose up -d
9. Wait up to 90s for /health to return "healthy"
10. Run tests/test_integration.sh
11. docker compose down --volumes  (always runs)
12. Upload tests/results/ as artifact
```

The CI must pass before any deploy is allowed (enforced via GitHub branch protection rules).

---

## 9. CD Pipeline & Zero-Downtime Deploy

**File:** `.github/workflows/deploy.yml`  
**Triggers:** Push to `main`

### Pipeline Steps

```
1. Checkout code
2. Compute lowercase image name from repo (ghcr.io/owner/statuspulse)
3. Log in to ghcr.io using GITHUB_TOKEN
4. Build and push Docker image
   └── Tags: :latest and :<commit-sha>
5. SSH into server (appleboy/ssh-action)
   ├── Install Docker if missing
   ├── Create /opt/statuspulse/scripts
   ├── Write docker-compose.yml via python3 (avoids heredoc indentation bugs)
   ├── Write scripts/deploy.sh via python3
   ├── chmod +x deploy.sh
   ├── Init .env if missing
   └── Run: cd /opt/statuspulse && bash scripts/deploy.sh
6. Post-deployment health check (from GitHub runner → HTTPS endpoint)
7. On success: comment on GitHub Issue
8. On failure: SSH back in and run deploy.sh rollback
9. On failure: comment on GitHub Issue with failure notice
```

### deploy.sh Logic

```
deploy.sh
├── Normal mode
│   ├── Save current tag → .previous_tag
│   ├── Save new tag → .current_tag
│   ├── docker pull <image>:<sha>
│   ├── docker compose up -d --no-deps api
│   ├── Health check (10 attempts × 5s)
│   │   ├── PASS → log success, exit 0
│   │   └── FAIL → restore previous tag, docker compose up -d --no-deps api
│   │              health check again → log result, exit 1
└── Rollback mode (bash deploy.sh rollback)
    ├── Read .previous_tag
    ├── docker compose up -d api
    └── Health check → log result
```

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `DEPLOY_HOST` | Server hostname or IP |
| `DEPLOY_USER` | SSH username (e.g. `deploy`) |
| `DEPLOY_PASSWORD` | SSH password |
| `DEPLOY_SSH_PORT` | SSH port (e.g. `2222`) |

---

## 10. Deployment Walkthrough (Screenshots)

The following screenshots document the CI/CD pipeline running end-to-end.

### Initial Project Setup

![Project setup](photo/Screenshot%20from%202026-05-05%2020-43-00.png)

*Initial project state — repository structure and configuration before the first pipeline run.*

---

### CI Pipeline — Lint & Build

![CI lint and build](photo/Screenshot%20from%202026-05-06%2017-20-53.png)

*GitHub Actions CI job: ruff linting and Dockerfile hadolint scan passing.*

---

### CI Pipeline — Integration Tests

![CI integration tests](photo/Screenshot%20from%202026-05-06%2017-21-18.png)

*Full stack started in CI, integration tests running against the live stack.*

---

### CI Pipeline — Tests Passing

![CI tests passing](photo/Screenshot%20from%202026-05-06%2017-21-24.png)

*All integration tests pass. Stack torn down cleanly after.*

---

### Deploy Pipeline — Image Build & Push

![Image build and push](photo/Screenshot%20from%202026-05-06%2017-21-36.png)

*Deploy workflow: Docker image built and pushed to ghcr.io tagged with the commit SHA.*

---

### Deploy Pipeline — SSH into Server

![SSH deploy step](photo/Screenshot%20from%202026-05-06%2017-21-46.png)

*appleboy/ssh-action connecting to the server, writing docker-compose.yml and deploy.sh.*

---

### Deploy Pipeline — Docker Pull on Server

![Docker pull](photo/Screenshot%20from%202026-05-06%2017-21-54.png)

*Server pulling the new image from ghcr.io by commit SHA.*

---

### Deploy Pipeline — Container Start

![Container start](photo/Screenshot%20from%202026-05-06%2017-22-14.png)

*`docker compose up -d --no-deps api` starting the new container.*

---

### Deploy Pipeline — Health Check

![Health check](photo/Screenshot%20from%202026-05-06%2017-22-24.png)

*Post-deploy health check polling `/health` — returns `healthy`.*

---

### Deploy Pipeline — Success

![Deploy success](photo/Screenshot%20from%202026-05-06%2017-23-02.png)

*Deploy pipeline completes successfully. GitHub Issue comment posted.*

---

### Deploy Pipeline — Rollback Triggered

![Rollback](photo/Screenshot%20from%202026-05-06%2017-23-51.png)

*Example of automatic rollback: health check failed, previous image restored.*

---

### Debugging — SSH Action Error (Fixed)

![SSH action error](photo/Screenshot%20from%202026-05-06%2018-07-46.png)

*`unknown shorthand flag: 'd' in -d` error caused by heredoc indentation writing leading spaces into the deploy script. Fixed by switching to `python3 + textwrap.dedent()`.*

---

### Fix Applied — python3 Write

![Fix applied](photo/Screenshot%20from%202026-05-06%2018-20-21.png)

*After fix: docker-compose.yml and deploy.sh written cleanly with no leading spaces. `docker compose up -d` parses correctly.*

---

### Final Successful Run

![Final run](photo/Screenshot%20from%202026-05-06%2018-43-51.png)

*Full pipeline green end-to-end after all fixes applied.*

---

### Project Overview / Diagram

![Project overview](photo/Pasted%20image.png)

*High-level overview of the StatusPulse system — services, flow, and components.*

---

### Post-Fix Pipeline Run — Step 1

![Post-fix run step 1](photo/Screenshot%20from%202026-05-06%2021-29-20.png)

*New pipeline run after all heredoc indentation fixes. Docker image built and pushed to ghcr.io successfully.*

---

### Post-Fix Pipeline Run — Step 2

![Post-fix run step 2](photo/Screenshot%20from%202026-05-06%2021-29-48.png)

*SSH deploy step: server setup, docker-compose.yml and deploy.sh written cleanly via python3. Image pulled and container started.*

---

### Post-Fix Pipeline Run — Fully Green

![Post-fix run fully green](photo/Screenshot%20from%202026-05-06%2021-32-51.png)

*All pipeline steps passing — build, push, deploy, health check, and success notification. Zero-downtime deploy confirmed working.*

---

## 11. Monitoring & Alerting

### Health Monitor (`scripts/health-monitor.sh`)

Runs every 5 minutes via cron. Checks:

| Check | Threshold | Action on Failure |
|---|---|---|
| `/health` HTTP status | Must return 200 + `"status":"healthy"` | Webhook alert |
| Disk usage | > 80% | Webhook alert |
| Memory usage | > 90% | Webhook alert |
| Docker containers | Must be running | Webhook alert |
| TLS certificate expiry | < 14 days remaining | Webhook alert |

**Setup:**
```bash
# /etc/cron.d/statuspulse-monitor
*/5 * * * * deploy /opt/statuspulse/scripts/health-monitor.sh
```

Alerts are sent as JSON POST to `$ALERT_WEBHOOK_URL` (Slack, Discord, PagerDuty, etc.).

Logs: `/var/log/statuspulse-monitor.log`

### Caddy — Automatic HTTPS

Caddy handles TLS certificate provisioning and renewal via Let's Encrypt automatically. No manual cert management needed.

Security headers applied to all responses:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Strict-Transport-Security` with 1-year max-age + preload
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Server` header removed

Rate limiting: 100 requests/minute per IP.

---

## 12. Backup & Restore

### Backup (`scripts/backup.sh`)

- Dumps PostgreSQL via `pg_dump` inside the running container
- Compresses with gzip
- Saves to `/opt/statuspulse/backups/`
- Keeps the last 7 backups (older ones deleted automatically)
- Optionally uploads to S3 if `$S3_BUCKET` is set

```bash
# Manual run
bash scripts/backup.sh

# Automated — daily at 2am
# 0 2 * * * /opt/statuspulse/scripts/backup.sh
```

Backup filename format: `statuspulse_db_YYYY-MM-DD_HHMMSS.sql.gz`

### Restore

```bash
gunzip -c backups/statuspulse_db_2026-05-06_020000.sql.gz \
  | docker compose exec -T db psql -U statuspulse statuspulse
```

---

## 13. Environment Variables Reference

Copy `.env.example` to `.env` and fill in values before starting.

| Variable | Default | Description |
|---|---|---|
| `APP_PORT` | `8000` | Host port the API binds to |
| `DB_HOST` | `db` | PostgreSQL hostname (Docker service name) |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `statuspulse` | Database name |
| `DB_USER` | `statuspulse` | Database user |
| `DB_PASSWORD` | — | **Required.** Database password |
| `REDIS_HOST` | `redis` | Redis hostname |
| `REDIS_PORT` | `6379` | Redis port |
| `REDIS_PASSWORD` | — | Redis password (optional) |
| `DOMAIN` | `localhost` | Domain for Caddy TLS + health monitor cert check |
| `ACME_EMAIL` | — | Email for Let's Encrypt registration |
| `ALERT_WEBHOOK_URL` | — | Webhook URL for health monitor alerts |
| `S3_BUCKET` | — | S3 bucket name for backup uploads |

---

## 14. Makefile Reference

| Target | Command | Description |
|---|---|---|
| `make build` | `docker compose build` | Build the API Docker image |
| `make up` | `docker compose up -d` | Start all services in background |
| `make down` | `docker compose down` | Stop all services |
| `make logs` | `docker compose logs -f api` | Tail API logs |
| `make test` | `curl /health` | Quick health check |
| `make clean` | `docker compose down --rmi all --volumes` | Full teardown including images and volumes |
| `make shell` | `docker compose exec api bash` | Shell into running API container |
| `make backup` | `bash scripts/backup.sh` | Run database backup |
| `make health` | `bash scripts/health-monitor.sh` | Run health monitor manually |

---

## 15. Security

- **Non-root container:** API runs as `appuser`, not root
- **Multi-stage build:** Build tools not present in the final image
- **SSH hardening:** Custom port (2222), root login disabled, password auth disabled
- **Firewall:** UFW denies all inbound except SSH/80/443
- **TLS:** Caddy auto-provisions and renews Let's Encrypt certificates
- **Security headers:** HSTS, X-Frame-Options, X-Content-Type-Options on all responses
- **Rate limiting:** 100 req/min per IP via Caddy
- **Secrets:** All credentials passed via GitHub Secrets, never hardcoded
- **Unattended upgrades:** OS security patches applied automatically
- **Memory limits:** Each container capped (api: 256MB, db: 256MB, redis: 128MB)

---

## 16. Troubleshooting

**Services not starting**
```bash
docker compose ps
docker compose logs db
docker compose logs api
```

**Health check returning `degraded`**
```bash
curl http://localhost:8000/health
# Check DB_HOST, DB_USER, DB_PASSWORD in .env
# Ensure db and redis containers are healthy: docker compose ps
```

**`docker compose up -d` fails with `unknown shorthand flag: 'd'`**

This happens when `docker-compose.yml` or `deploy.sh` is written with leading whitespace (heredoc indentation bug). The fix is to write files via `python3 + textwrap.dedent()` in the deploy workflow. See the deploy workflow for the corrected implementation.

**Port already in use**
```bash
# Change APP_PORT in .env
make down && make up
```

**Out of disk space**
```bash
docker system prune -f
bash scripts/backup.sh   # rotates old backups
```

**Rollback manually**
```bash
cd /opt/statuspulse
bash scripts/deploy.sh rollback
```

**Check deploy logs**
```bash
cat /var/log/statuspulse-deploy.log
cat /var/log/statuspulse-monitor.log
cat /var/log/statuspulse-backup.log
```
