# Deploy Troubleshooting Guide

## Current Issue: SSH Authentication Failure

**Error**: `handshake failed: ssh: unable to authenticate, attempted methods [none password], no supported methods remain`

### Root Cause
The Azure VM likely has password authentication disabled in SSH configuration by default. GitHub Actions deploy workflow uses password-based SSH authentication.

---

## Solution Steps

### Option 1: Enable Password Authentication (Quick Fix)

**On the server** (SSH in manually first):

```bash
# SSH into your server manually
ssh statusplus@20.198.8.123

# Run the fix script
cd /opt/statuspulse
wget https://raw.githubusercontent.com/jatavkapil123/StatusPulse/main/scripts/enable-ssh-password.sh
chmod +x enable-ssh-password.sh
./enable-ssh-password.sh
```

Or manually:
```bash
# Backup config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Enable password auth
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Restart SSH
sudo systemctl restart sshd
```

### Option 2: Use SSH Key Authentication (More Secure)

1. **Generate SSH key pair** (on your local machine):
   ```bash
   ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/statuspulse_deploy
   ```

2. **Copy public key to server**:
   ```bash
   ssh-copy-id -i ~/.ssh/statuspulse_deploy.pub statusplus@20.198.8.123
   ```

3. **Update GitHub Secrets**:
   - Remove: `DEPLOY_PASSWORD`
   - Add: `DEPLOY_SSH_KEY` = (paste content of `~/.ssh/statuspulse_deploy` private key)

4. **Update `.github/workflows/deploy.yml`**:
   ```yaml
   - name: Setup server and deploy
     uses: appleboy/ssh-action@v1.0.3
     with:
       host: ${{ secrets.DEPLOY_HOST }}
       username: ${{ secrets.DEPLOY_USER }}
       key: ${{ secrets.DEPLOY_SSH_KEY }}  # Changed from password
       port: ${{ secrets.DEPLOY_SSH_PORT }}
       # ... rest stays same
   ```

---

## Verify GitHub Secrets

Go to: `https://github.com/jatavkapil123/StatusPulse/settings/secrets/actions`

Required secrets:
- `DEPLOY_HOST` = `20.198.8.123`
- `DEPLOY_USER` = `statusplus`
- `DEPLOY_PASSWORD` = `@Kapilj12345` (ensure no extra spaces/quotes)
- `DEPLOY_SSH_PORT` = `22`

**Common mistakes**:
- Extra spaces before/after password
- Quotes around password (don't add quotes)
- Wrong username (should be `statusplus` not `statusplus@20.198.8.123`)

---

## Test SSH Connection Manually

Before running GitHub Actions, test SSH manually:

```bash
# Test password auth
ssh statusplus@20.198.8.123

# If it asks for password and works → GitHub Secret might have typo
# If it fails → password auth is disabled on server
```

Check SSH config on server:
```bash
ssh statusplus@20.198.8.123
grep "^PasswordAuthentication" /etc/ssh/sshd_config
# Should show: PasswordAuthentication yes
```

---

## Re-run Terraform (For Future Deployments)

The `terraform/userdata.sh.tpl` has been updated to enable password authentication by default. If you destroy and recreate the VM:

```bash
cd terraform
terraform destroy
terraform apply
```

New VMs will have password auth enabled automatically.

---

## Security Note

**After fixing the deploy issue**, change the password:

```bash
ssh statusplus@20.198.8.123
sudo passwd statusplus
# Enter new password
```

Then update GitHub Secret `DEPLOY_PASSWORD` with the new password.

**Better**: Switch to SSH key authentication (Option 2 above) for production use.
