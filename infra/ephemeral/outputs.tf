output "instance_id" {
  value = aws_instance.node.id
}

output "public_ip" {
  value = aws_instance.node.public_ip
}

output "api_url" {
  value = "http://${aws_instance.node.public_ip}:30080"
}
