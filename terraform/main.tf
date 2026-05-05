terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ── Security Group ─────────────────────────────────────────────────────────────
resource "aws_security_group" "statuspulse" {
  name        = "statuspulse-sg"
  description = "StatusPulse firewall rules"

  ingress {
    description = "Custom SSH"
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "statuspulse-sg" }
}

# ── EC2 Instance ───────────────────────────────────────────────────────────────
resource "aws_instance" "statuspulse" {
  ami                    = var.ami
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.statuspulse.id]

  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    ssh_port = var.ssh_port
    deploy_user = var.deploy_user
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "statuspulse" }
}

# ── Elastic IP ─────────────────────────────────────────────────────────────────
resource "aws_eip" "statuspulse" {
  instance = aws_instance.statuspulse.id
  domain   = "vpc"
  tags     = { Name = "statuspulse-eip" }
}
