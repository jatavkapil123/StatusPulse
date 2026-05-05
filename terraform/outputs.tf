output "server_ip" {
  description = "Public IP of the StatusPulse server"
  value       = aws_eip.statuspulse.public_ip
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -p ${var.ssh_port} ${var.deploy_user}@${aws_eip.statuspulse.public_ip}"
}
