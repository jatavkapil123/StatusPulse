#!/bin/bash
set -e

# Create deploy user
useradd -m -s /bin/bash ${deploy_user}
usermod -aG docker ${deploy_user} 2>/dev/null || true

# Harden SSH
sed -i 's/^#Port 22/Port ${ssh_port}/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Firewall
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ${ssh_port}/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Install Docker
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Swap (1GB)
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Auto security updates
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# Deploy directory
mkdir -p /opt/statuspulse
chown ${deploy_user}:${deploy_user} /opt/statuspulse
