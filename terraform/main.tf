terraform {
  required_version = ">= 1.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ── Resource Group ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "statuspulse" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# ── Virtual Network ────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "statuspulse" {
  name                = "${var.project_name}-vnet"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.statuspulse.location
  resource_group_name = azurerm_resource_group.statuspulse.name

  tags = var.tags
}

resource "azurerm_subnet" "statuspulse" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.statuspulse.name
  virtual_network_name = azurerm_virtual_network.statuspulse.name
  address_prefixes     = [var.subnet_address_prefix]
}

# ── Public IP (Static) ─────────────────────────────────────────────────────────
resource "azurerm_public_ip" "statuspulse" {
  name                = "${var.project_name}-pip"
  location            = azurerm_resource_group.statuspulse.location
  resource_group_name = azurerm_resource_group.statuspulse.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.availability_zone]
  domain_name_label   = var.dns_label != "" ? var.dns_label : null

  tags = var.tags
}

# ── Network Security Group ─────────────────────────────────────────────────────
resource "azurerm_network_security_group" "statuspulse" {
  name                = "${var.project_name}-nsg"
  location            = azurerm_resource_group.statuspulse.location
  resource_group_name = azurerm_resource_group.statuspulse.name

  # SSH
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.ssh_port)
    source_address_prefix      = var.ssh_source_cidr
    destination_address_prefix = "*"
  }

  # HTTP — needed for Let's Encrypt ACME challenge
  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTPS
  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Uptime Kuma
  security_rule {
    name                       = "Allow-UptimeKuma"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3001"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Deny all other inbound
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# ── Network Interface ──────────────────────────────────────────────────────────
resource "azurerm_network_interface" "statuspulse" {
  name                = "${var.project_name}-nic"
  location            = azurerm_resource_group.statuspulse.location
  resource_group_name = azurerm_resource_group.statuspulse.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.statuspulse.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.statuspulse.id
  }

  tags = var.tags
}

resource "azurerm_network_interface_security_group_association" "statuspulse" {
  network_interface_id      = azurerm_network_interface.statuspulse.id
  network_security_group_id = azurerm_network_security_group.statuspulse.id
}

# ── Linux Virtual Machine ──────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "statuspulse" {
  name                = var.project_name
  resource_group_name = azurerm_resource_group.statuspulse.name
  location            = azurerm_resource_group.statuspulse.location
  size                = var.vm_size
  admin_username      = var.admin_username
  zone                = var.availability_zone

  network_interface_ids = [azurerm_network_interface.statuspulse.id]

  # Password auth — set disable_password_authentication = true and
  # provide admin_ssh_key block to switch to key-based auth
  admin_password                  = var.admin_password
  disable_password_authentication = false

  os_disk {
    name                 = "${var.project_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  # Ubuntu 24.04 LTS — matches existing server
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Bootstrap script: installs Docker, configures firewall, swap, cron jobs
  custom_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    ssh_port       = var.ssh_port
    admin_username = var.admin_username
    swap_size_gb   = var.swap_size_gb
  }))

  tags = var.tags
}

# ── DNS Record (optional — only created when dns_zone_name is set) ─────────────
resource "azurerm_dns_a_record" "statuspulse" {
  count = var.dns_zone_name != "" ? 1 : 0

  name                = var.dns_record_name
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group != "" ? var.dns_zone_resource_group : azurerm_resource_group.statuspulse.name
  ttl                 = 300
  records             = [azurerm_public_ip.statuspulse.ip_address]

  tags = var.tags
}
