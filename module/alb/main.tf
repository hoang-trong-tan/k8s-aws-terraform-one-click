# 2. Khởi tạo Application Load Balancer
resource "aws_lb" "main_alb" {
  name               = "k8s-lab-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg]
  subnets            = var.public_subnet_ids
}

# 3. Target Group trỏ vào NodePort 30000 của K8s
resource "aws_lb_target_group" "k8s_tg" {
  name        = "k8s-nodeport-tg"
  port        = 30000 # Cổng NodePort chúng ta sẽ expose trong Kubernetes
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "30000"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# 4. Listener lắng nghe cổng 80 của ALB và forward vào Target Group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_tg.arn
  }
}

# 5. Gắn con EC2 Minikube vào Target Group
resource "aws_lb_target_group_attachment" "ec2_attachment" {
  target_group_arn = aws_lb_target_group.k8s_tg.arn
  target_id        = var.instance_id
}