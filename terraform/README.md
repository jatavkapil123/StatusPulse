# Terraform — StatusPulse Infrastructure

Provisions an AWS EC2 instance with hardened SSH, UFW firewall, Docker, swap, and auto-updates.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- AWS credentials configured (`aws configure` or env vars)
- An existing EC2 key pair

## Usage

```bash
cd terraform

# 1. Initialize
terraform init

# 2. Review plan
terraform plan -var="key_name=your-key-pair"

# 3. Apply
terraform apply -var="key_name=your-key-pair"

# 4. Get server IP
terraform output server_ip
```

## Variables

| Variable       | Default         | Description                        |
|----------------|-----------------|------------------------------------|
| region         | us-east-1       | AWS region                         |
| ami            | Ubuntu 22.04    | AMI ID (update per region)         |
| instance_type  | t3.micro        | EC2 instance type                  |
| key_name       | (required)      | EC2 key pair name                  |
| ssh_port       | 2222            | Hardened SSH port                  |
| deploy_user    | deploy          | Non-root deploy user               |

## Teardown

```bash
terraform destroy -var="key_name=your-key-pair"
```
