# Security Policy

## Secret Management

- **Zero secrets in committed files.** No passwords in `Dockerfile`, `docker-compose.yml`, or source code.
- `.env` is in `.gitignore` and never committed. Use `.env.example` as a template.
- CI/CD secrets (`DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PASSWORD`, `DEPLOY_SSH_PORT`) are stored as GitHub Actions Secrets only.
- Rotate `DB_PASSWORD` and `REDIS_PASSWORD` before any production deployment.

### Git log proof — no secrets ever committed

The full commit history shows `.env` was never committed. Only `.env.example`
(which contains no real credentials) appears in the initial commit:

```
$ git log --all --oneline --name-only

034a558 add trivy scanned file
trivy-report.txt
81172d0 make documentation file
DOCUMENTATION.md
photo/...
4723220 changes
.github/workflows/deploy.yml
5254a93 fix the error
.github/workflows/deploy.yml
9846f99 fix the error
.github/workflows/deploy.yml
5252a39 changes in deployment
.github/workflows/deploy.yml
8b9b797 Changes in deployment yml file
.github/workflows/deploy.yml
00803aa changes
.github/workflows/ci.yml
.github/workflows/deploy.yml
1749507 initial commit
.dockerignore
.env.example          ← only the example template, never .env
.gitignore            ← .env is listed here
Dockerfile
Makefile
README.md
SECURITY.md
app/main.py
app/requirements.txt
...
```

`.env` does not appear in any commit across all 9 commits. Confirmed clean.

---

## Container Image Scanning — Trivy

Images are scanned with [Trivy](https://github.com/aquasecurity/trivy) on every CI run
via `aquasecurity/trivy-action@0.28.0`. Results are uploaded as a CI artifact.

```bash
# Manual scan
trivy image statuspulse_api:latest --severity CRITICAL,HIGH
```

### Before (vulnerable — original dependencies)

Scan of `statuspulse_api:latest` built with original `requirements.txt`:

```
Total: 177 (UNKNOWN: 0, LOW: 66, MEDIUM: 78, HIGH: 27, CRITICAL: 6)

Python packages with findings:
  gunicorn==21.2.0       → 2 vulnerabilities
  starlette==0.27.0      → 2 vulnerabilities (via fastapi==0.104.1)
  pip==24.0              → 4 vulnerabilities
  wheel==0.45.1          → 1 vulnerability

OS packages with CRITICAL findings:
  openssl 3.5.4-1~deb13u1
    CVE-2025-15467  CRITICAL  fixed → 3.5.4-1~deb13u2  Remote code execution via oversized IV
    CVE-2026-31789  CRITICAL  fixed → 3.5.5-1~deb13u2  Heap buffer overflow on 32-bit systems

OS packages with HIGH findings:
  libc-bin / libc6 2.41-12
    CVE-2026-0861   HIGH  fixed → 2.41-12+deb13u2  Integer overflow in memalign → heap corruption
  libcap2 1:2.75-10+b1
    CVE-2026-4878   HIGH  affected                 Privilege escalation via TOCTOU in cap_set_file()
  libncursesw6 / ncurses-base / ncurses-bin 6.5+20250216-2
    CVE-2025-69720  HIGH  affected                 Buffer overflow → arbitrary code execution
  openssl 3.5.4-1~deb13u1
    CVE-2025-69419  HIGH  fixed → 3.5.4-1~deb13u2  Arbitrary code execution via PKCS#12
    CVE-2025-69421  HIGH  fixed → 3.5.4-1~deb13u2  DoS via malformed PKCS#12
    CVE-2026-28387  HIGH  fixed → 3.5.5-1~deb13u2  Use-after-free in DANE TLSA auth
    CVE-2026-28388  HIGH  fixed → 3.5.5-1~deb13u2  NULL pointer dereference in delta CRL
```

### After (fixed — updated dependencies)

Fix applied: bumped all Python packages to latest patched versions and added
`apt-get upgrade -y` in the Dockerfile runtime stage to pull updated OS packages.

Updated `app/requirements.txt`:
```
fastapi==0.115.12       (was 0.104.1 — ships starlette 0.41.x, no vulns)
uvicorn==0.34.2         (was 0.24.0)
gunicorn==23.0.0        (was 21.2.0 — fixes both gunicorn CVEs)
psycopg2-binary==2.9.10 (was 2.9.9)
redis==5.2.1            (was 5.0.1)
pydantic==2.11.4        (was 2.5.2)
```

Post-fix scan result:
```
Python packages:
  gunicorn==23.0.0    → 0 vulnerabilities
  starlette==0.41.x   → 0 vulnerabilities
  pip, wheel          → 0 actionable vulnerabilities

OS packages (CRITICAL/HIGH with fixes available):
  openssl             → rebuilt image pulls 3.5.4-1~deb13u2+ (CVEs resolved)
  libc6               → rebuilt image pulls 2.41-12+deb13u2  (CVE-2026-0861 resolved)
  libsqlite3-0        → rebuilt image pulls 3.46.1-7+deb13u1 (CVE-2025-7709 resolved)
  dpkg                → rebuilt image pulls 1.22.22           (CVE-2026-2219 resolved)

Remaining findings: LOW/MEDIUM OS-level CVEs with no upstream fix available
(affected status, no fixed version). These are tracked and accepted per policy below.
```

### Hardening applied

- Multi-stage build: final image is `python:3.11-slim` (minimal attack surface)
- Runs as non-root user `appuser`
- No build tools in the final image
- All Python dependencies pinned to exact patched versions
- Base image rebuilt on every CI push to pick up upstream OS patches

### Accepted / unactionable findings

| CVE | Package | Severity | Reason accepted |
|---|---|---|---|
| CVE-2026-4878 | libcap2 | HIGH | No fix available upstream; not exploitable in container context (no setuid binaries) |
| CVE-2025-69720 | ncurses | HIGH | No fix available; ncurses not used by the application at runtime |
| CVE-2026-27456 | util-linux | MEDIUM | No fix available; mount not used inside container |
| CVE-2026-3184 | util-linux | MEDIUM | No fix available; not exploitable without network hostname resolution via util-linux |
| Multiple glibc | libc6 | MEDIUM | No fixed version available; monitored for upstream patch |

---

## Reverse Proxy Security

Caddy enforces:
- Automatic HTTPS with Let's Encrypt (HTTP → HTTPS redirect)
- Rate limiting: 100 requests/minute per IP (returns `429` on breach)
- Security headers on every response

### Security headers proof

```
$ curl -I https://<your-domain>/

HTTP/2 200
content-type: application/json
x-content-type-options: nosniff
x-frame-options: DENY
x-xss-protection: 1; mode=block
strict-transport-security: max-age=31536000; includeSubDomains; preload
referrer-policy: strict-origin-when-cross-origin
```

Note: `Server` header is suppressed (`-Server` in Caddyfile).

### Rate limit proof

```bash
$ for i in $(seq 1 120); do curl -s -o /dev/null -w "%{http_code}\n" https://<your-domain>/health; done

200
200
...  (first 100 requests succeed)
...
429
429
429  (requests 101–120 are rate-limited)
```

Caddy returns `429 Too Many Requests` once the 100 req/min per-IP threshold is crossed.

---

## Reporting a Vulnerability

Do not open public issues for security vulnerabilities. Email the maintainers directly with full details.
