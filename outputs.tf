output "public_ip_of_VPN" {
  value = aws_eip.vpn.public_ip
}