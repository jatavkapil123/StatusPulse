# Terraform — Azure Infrastructure for StatusPulse

Recreates the entire StatusPulse production infrastructure from scratch on Azure using Terraform.

## What gets provisioned

| Resource | Name | Details |
|---|---|---|
| Resource Group | `statuspulse-rg` | Container for all resources |
| Virtual Network | `statuspulse-vnet` | `10.1.0.0/16` |
| Subnet | `default` | `10.1.0.0/24` |
| Public IP | `statuspulse-pip` | Static, Standard SKU |
| Network Security Group | `statuspulse-nsg` | Allows SSH, 80, 443, 3001 inbound |
| Network Interface | `statuspulse-nic` | Connects VM to subnet + public IP |
| Linux VM | `statuspulse` | Ubuntu 24.04 LTS, Standard_B2as_v2, 30GB Premium SSD |
| DNS A Record | optional | Created only when `dns_zone_name` is set |

## What the VM bootstrap does (userdata.sh.tpl)

On first boot, the VM automatically:

1. Installs Docker CE + docker-compose-plugin
2. Hardens SSH (configurable port, no root login, max 3 auth attempts)
3. Configures UFW firewall (deny all inbound except SSH/80/443/3001)
4. Creates a 2GB swap file
5. Enables unattended security upgrades
6. Creates `/opt/statuspulse/` directory structure
7. Installs cron jobs (daily backup at 2am, health monitor every 5 min)
8. Starts Uptime Kuma on port 3001

## Prerequisites

### 1. Install tools

```bash
# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### 2. Authenticate to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"

# Verify
az account show
```

## Usage

### Step 1 — Initialise

```bash
cd terraform
terraform init
```

### Step 2 — Review the plan

```bash
terraform plan -var="admin_password=YourStr0ng!Pass"
```

### Step 3 — Apply

```bash
terraform apply -var="admin_password=YourStr0ng!Pass"
```

Type `yes` when prompted. Takes ~2 minutes.

### Step 4 — Get outputs

```bash
terraform output
```

Example output:
```
server_ip    = "4.186.31.153"
ssh_command  = "ssh -p 22 statusplus@4.186.31.153"
resource_group = "statuspulse-rg"
app_url      = "http://4.186.31.153"
fqdn         = ""
dns_record   = "DNS record not configured"
```

### Step 5 — Connect and verify bootstrap

```bash
ssh statusplus@4.186.31.153

# Check bootstrap log
sudo cat /var/log/statuspulse-bootstrap.log

# Verify Docker
docker --version
docker compose version

# Verify Uptime Kuma
docker ps | grep uptime-kuma
```

### Step 6 — Deploy the application

After the VM is ready, push to `main` branch — the GitHub Actions deploy workflow will SSH in and deploy the stack automatically.

Or manually:

```bash
ssh statusplus@4.186.31.153
cd /opt/statuspulse
cp .env.example .env && nano .env   # set DB_PASSWORD etc.
docker compose up -d
```

## Variables reference

| Variable | Default | Required | Description |
|---|---|---|---|
| `location` | `East US` | No | Azure region |
| `resource_group_name` | `statuspulse-rg` | No | Resource group name |
| `project_name` | `statuspulse` | No | Prefix for all resource names |
| `vm_size` | `Standard_B2as_v2` | No | VM size (2 vCPU, 8GB RAM) |
| `admin_username` | `statusplus` | No | VM admin username |
| `admin_password` | — | **Yes** | VM admin password (sensitive) |
| `os_disk_size_gb` | `30` | No | OS disk size in GB |
| `ssh_port` | `22` | No | SSH port |
| `ssh_source_cidr` | `*` | No | Restrict SSH to your IP: `1.2.3.4/32` |
| `swap_size_gb` | `2` | No | Swap file size in GB |
| `vnet_address_space` | `10.1.0.0/16` | No | VNet CIDR |
| `subnet_address_prefix` | `10.1.0.0/24` | No | Subnet CIDR |
| `dns_zone_name` | `""` | No | Azure DNS zone (leave empty to skip) |
| `dns_record_name` | `@` | No | DNS record name |
| `dns_label` | `""` | No | Azure public IP DNS label |
| `tags` | see variables.tf | No | Tags applied to all resources |

## Using a tfvars file (recommended)

Create `terraform/terraform.tfvars` (already in `.gitignore`):

```hcl
location            = "East US"
resource_group_name = "statuspulse-rg"
admin_password      = "YourStr0ng!Pass"
ssh_source_cidr     = "YOUR_IP/32"
dns_label           = "statuspulse"
```

Then run:
```bash
terraform apply
```

## Optional: DNS with Azure DNS

If you have a domain managed in Azure DNS:

```hcl
dns_zone_name           = "yourdomain.com"
dns_record_name         = "status"
dns_zone_resource_group = "dns-rg"   # if DNS zone is in a different RG
```

This creates `status.yourdomain.com → VM public IP`.

## Destroy

```bash
terraform destroy -var="admin_password=YourStr0ng!Pass"
```

This deletes **all** resources in the resource group including the VM, disk, IP, and network.
