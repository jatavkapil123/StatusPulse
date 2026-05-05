# Security Policy

## Secret Management

- **Zero secrets in committed files.** No passwords in `Dockerfile`, `docker-compose.yml`, or source code.
- `.env` is in `.gitignore` and never committed. Use `.env.example` as a template.
- CI/CD secrets (`DEPLOY_HOST`, `DEPLOY_SSH_KEY`, etc.) are stored as GitHub Actions Secrets only.
- Rotate `DB_PASSWORD` and `REDIS_PASSWORD` before any production deployment.

## Container Image Scanning

Images are scanned with [Trivy](https://github.com/aquasecurity/trivy) on every CI run:

```bash
trivy image ghcr.io/your-org/statuspulse:latest
```

### Hardening applied
- Multi-stage build: final image is `python:3.11-slim` (minimal attack surface)
- Runs as non-root user `appuser`
- No shell or package manager in final image beyond what Python slim provides
- Dependencies pinned to exact versions in `requirements.txt`

### Known findings & mitigations
| Severity | Package | Fix |
|----------|---------|-----|
| Any HIGH/CRITICAL | Base OS packages | Rebuild regularly; `python:3.11-slim` is updated upstream |

## Reverse Proxy Security

Caddy enforces:
- Automatic HTTPS with Let's Encrypt (HTTP → HTTPS redirect)
- Rate limiting: 100 requests/minute per IP (returns 429 on breach)
- Headers: `X-Content-Type-Options`, `X-Frame-Options`, `Strict-Transport-Security`, `X-XSS-Protection`

## Reporting a Vulnerability

Do not open public issues for security vulnerabilities. Email the maintainers directly with full details.
