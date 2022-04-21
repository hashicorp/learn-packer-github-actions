output "aws_public_ip" {
  value = aws_instance.hashicups.public_ip
}