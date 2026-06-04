output "public_ip" {
  value       = aws_instance.name.public_ip
  description = "Public IP của EC2 chạy Minikube"
}

output "instance_id" {
  value = aws_instance.name.id
}