variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "ami" {
  description = "Ubuntu 22.04 LTS AMI ID (region-specific)"
  default     = "ami-0c7217cdde317cfec"  # us-east-1 Ubuntu 22.04
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
}

variable "ssh_port" {
  description = "Custom SSH port (hardened)"
  default     = 2222
}

variable "deploy_user" {
  description = "Non-root deploy user"
  default     = "deploy"
}
