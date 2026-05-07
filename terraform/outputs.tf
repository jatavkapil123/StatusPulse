output "server_ip" {
  description = "Public IP address of the StatusPulse VM"
  value       = azurerm_public_ip.statuspulse.ip_address
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh -p ${var.ssh_port} ${var.admin_username}@${azurerm_public_ip.statuspulse.ip_address}"
}

output "resource_group" {
  description = "Resource group containing all StatusPulse resources"
  value       = azurerm_resource_group.statuspulse.name
}

output "fqdn" {
  description = "Fully qualified domain name (only set when dns_label is configured)"
  value       = azurerm_public_ip.statuspulse.fqdn
}

output "dns_record" {
  description = "DNS A record FQDN (only set when dns_zone_name is configured)"
  value       = var.dns_zone_name != "" ? azurerm_dns_a_record.statuspulse[0].fqdn : "DNS record not configured"
}

output "app_url" {
  description = "Application URL"
  value       = var.dns_zone_name != "" ? "https://${var.dns_record_name}.${var.dns_zone_name}" : "http://${azurerm_public_ip.statuspulse.ip_address}"
}
