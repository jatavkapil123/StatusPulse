variable "location" {
  description = "Azure region where all resources will be created"
  default     = "Central India"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  default     = "statuspulse-rg"
}

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  default     = "statuspulse"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    project     = "statuspulse"
    environment = "production"
    managed_by  = "terraform"
  }
}

# ── Networking ─────────────────────────────────────────────────────────────────

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  default     = "10.1.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the default subnet"
  default     = "10.1.0.0/24"
}

variable "ssh_source_cidr" {
  description = "CIDR allowed to SSH into the VM. Restrict to your IP for hardening (e.g. '1.2.3.4/32')"
  default     = "*"
}

# ── VM ─────────────────────────────────────────────────────────────────────────

variable "vm_size" {
  description = "Azure VM size"
  default     = "Standard_B2as_v2"
}

variable "admin_username" {
  description = "Admin username for the VM"
  default     = "statusplus"
}

variable "admin_password" {
  description = "Admin password for the VM. Must meet Azure complexity requirements (12+ chars, upper, lower, digit, special)"
  sensitive   = true
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  default     = 30
}

variable "ssh_port" {
  description = "SSH port. Default is 22 (Azure NSG controls access)"
  default     = 22
}

variable "swap_size_gb" {
  description = "Swap file size in GB"
  default     = 2
}

variable "availability_zone" {
  description = "Azure availability zone for the VM and public IP (1, 2, or 3)"
  default     = "2"
}

# ── DNS (optional) ─────────────────────────────────────────────────────────────

variable "dns_zone_name" {
  description = "Azure DNS zone name for creating an A record. Leave empty to skip DNS record creation"
  default     = ""
}

variable "dns_record_name" {
  description = "DNS A record name (e.g. '@' for root, 'status' for status.yourdomain.com)"
  default     = "@"
}

variable "dns_zone_resource_group" {
  description = "Resource group containing the DNS zone. Defaults to the same resource group as the VM if empty"
  default     = ""
}

variable "dns_label" {
  description = "Azure public IP DNS label for a free *.region.cloudapp.azure.com hostname. Leave empty to skip"
  default     = ""
}
