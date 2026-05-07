#!/bin/bash
# enable-ssh-password.sh — Enable password authentication on existing server
# Run this ONCE on the server if SSH password auth is disabled

set -euo pipefail

echo "Enabling SSH password authentication..."

# Backup original config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)

# Enable password authentication
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Ensure it's set (add if not present)
if ! grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
  echo "PasswordAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
fi

# Restart SSH service
sudo systemctl restart sshd

echo "✓ Password authentication enabled. SSH service restarted."
echo "You can now use password-based SSH login."
