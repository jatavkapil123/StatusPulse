#!/bin/bash
# userdata.sh.tpl — Bootstrap script for StatusPulse Azure VM
# Runs once on first boot as root via cloud-init
set -euo pipefail

LOG=/var/log/statuspulse-bootstrap.log
exec > >(tee -a "$LOG") 2>&1

echo "[$(date)] === StatusPulse bootstrap started ==="

# ── Wait for apt lock ──────────────────────────────────────────────────────────
echo "[$(date)] Waiting for apt lock..."
for i in $(seq 1 30); do
  if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then break; fi
  sleep 5
done
apt-get update -qq

# ── Install base packages ──────────────────────────────────────────────────────
echo "[$(date)] Installing base packages..."
apt-get install -y -qq \
  ca-certificates curl gnupg ufw unattended-upgrades \
  python3 python3-pip jq git

# ── Install Docker CE ──────────────────────────────────────────────────────────
echo "[$(date)] Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

# Add admin user to docker group
usermod -aG docker ${admin_username}
echo "[$(date)] Docker installed."

# ── Harden SSH ─────────────────────────────────────────────────────────────────
echo "[$(date)] Hardening SSH..."
sed -i "s/^#Port 22/Port ${ssh_port}/" /etc/ssh/sshd_config
sed -i "s/^Port 22$/Port ${ssh_port}/" /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
# Limit auth attempts
grep -q "^MaxAuthTries" /etc/ssh/sshd_config \
  && sed -i 's/^MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config \
  || echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
systemctl restart sshd
echo "[$(date)] SSH hardened on port ${ssh_port}."

# ── Configure UFW firewall ─────────────────────────────────────────────────────
echo "[$(date)] Configuring UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ${ssh_port}/tcp comment "SSH"
ufw allow 80/tcp  comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw allow 3001/tcp comment "Uptime Kuma"
ufw --force enable
echo "[$(date)] UFW configured."

# ── Swap ───────────────────────────────────────────────────────────────────────
echo "[$(date)] Creating ${swap_size_gb}GB swap..."
if [ ! -f /swapfile ]; then
  fallocate -l ${swap_size_gb}G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
echo "[$(date)] Swap ready."

# ── Auto security updates ──────────────────────────────────────────────────────
echo "[$(date)] Enabling unattended upgrades..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
echo "[$(date)] Unattended upgrades enabled."

# ── Deploy directory ───────────────────────────────────────────────────────────
echo "[$(date)] Creating deploy directory..."
mkdir -p /opt/statuspulse/scripts
mkdir -p /opt/statuspulse/backups
mkdir -p /opt/statuspulse/caddy
chown -R ${admin_username}:${admin_username} /opt/statuspulse

# ── Cron jobs ──────────────────────────────────────────────────────────────────
echo "[$(date)] Installing cron jobs..."

# Daily backup at 2am
BACKUP_CRON="0 2 * * * ${admin_username} /opt/statuspulse/scripts/backup.sh >> /opt/statuspulse/backups/backup.log 2>&1"
echo "$BACKUP_CRON" > /etc/cron.d/statuspulse-backup
chmod 644 /etc/cron.d/statuspulse-backup

# Health monitor every 5 minutes
MONITOR_CRON="*/5 * * * * ${admin_username} /opt/statuspulse/scripts/health-monitor.sh >> /var/log/statuspulse-monitor.log 2>&1"
echo "$MONITOR_CRON" > /etc/cron.d/statuspulse-monitor
chmod 644 /etc/cron.d/statuspulse-monitor

echo "[$(date)] Cron jobs installed."

# ── Uptime Kuma (standalone container) ────────────────────────────────────────
echo "[$(date)] Starting Uptime Kuma..."
docker volume create uptime-kuma 2>/dev/null || true
docker run -d \
  --name uptime-kuma \
  --restart unless-stopped \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  louislam/uptime-kuma:1 || echo "[$(date)] Uptime Kuma already running or failed — skipping"

echo "[$(date)] === Bootstrap complete ==="
