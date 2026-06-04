output "alb_dns_name" {
  value       = aws_lb.main_alb.dns_name
  description = "Đường dẫn URL của Load Balancer để bạn truy cập ứng dụng"
}

