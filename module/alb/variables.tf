variable "vpc_id" {
  type        = string
  description = "ID của VPC"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Danh sách các Public Subnets để đặt ALB"
}

variable "instance_id" {
  type        = string
  description = "ID của con EC2 chạy Minikube để gắn vào Target Group"
}

variable "alb_sg" {
  type        = string
  description = "ID của Security Group dành cho ALB truyền từ module VPC"
}