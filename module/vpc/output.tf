output "aws_subnet" {
  value = aws_subnet.demo
}

output "aws_sg_alb" {
  value = aws_security_group.demo_sg_alb.id
}

output "aws_sg_ec2" {
  value = aws_security_group.demo_sg_ec2.id
}

output "vpc_id_demo" {
  value = aws_vpc.demo.id
}