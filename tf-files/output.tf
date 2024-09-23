# Output instance public IP
output "nginx_private_ip" {
  value = aws_instance.nginx[*].private_ip
  description = "The private IPs of the EC2 web servers"
}

# Output instance public IP
output "jumpbox_public_ip" {
  value = aws_instance.jumpbox.public_ip
  description = "The public IP of the EC2 jumpbox"
}

# Output the private SSH key for access
output "private_vm_key_pem" {
  value       = tls_private_key.ssh_key.private_key_pem
  description = "Private SSH key for EC2 access"
  sensitive   = true  # Mark as sensitive for security
}

# Output private IP of the Network Load Balancer
output "nlb_private_ip" {
  value       = data.aws_network_interface.nlb-network-interface.private_ip
  description = "The IP address of the NLB"
}

# Output the DNS name of the ALB
output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}


