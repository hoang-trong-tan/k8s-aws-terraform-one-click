data "aws_ami" "linux" {
  most_recent = true
  filter {
    name = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  owners = ["137112412989"]
}


resource "aws_instance" "name" {
  ami = data.aws_ami.linux.id
  instance_type = "t3.medium"
  subnet_id = var.subnet_id_for_ec2
  vpc_security_group_ids = [var.sg_id_for_ec2]
  user_data_replace_on_change = true
  tags = var.tags_ec2
  key_name = var.key_name
 
  user_data = <<-EOF
    #!/bin/bash
    # 1. Cập nhật hệ thống và cài đặt Docker
    yum update -y
    yum install -y docker socat
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user

    # 2. Cài đặt Kubectl
    curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.0/2024-01-04/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mv ./kubectl /usr/local/bin/kubectl

    # 3. Cài đặt Minikube
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    mv minikube /usr/local/bin/

    # 4. Khởi động Minikube dưới quyền ec2-user và cấp phép cho IP Public
    PUBLIC_IP=$(curl -s checkip.amazonaws.com)
    su - ec2-user -c "minikube start --driver=docker --apiserver-ips=$PUBLIC_IP"

    # 5. XÂY CẦU NỐI MẠNG (Port Forwarding)
    # Lấy IP ảo của Minikube bên trong Docker
    MINIKUBE_IP=$(su - ec2-user -c "minikube ip")
    
    # Nối cổng 8443 (Cho Terraform kết nối API)
    nohup socat TCP-LISTEN:8443,fork,bind=0.0.0.0 TCP:$MINIKUBE_IP:8443 > /dev/null 2>&1 &
    
    # Nối cổng 30000 (Cho ALB kết nối vào Nginx NodePort)
    nohup socat TCP-LISTEN:30000,fork,bind=0.0.0.0 TCP:$MINIKUBE_IP:30000 > /dev/null 2>&1 &
  EOF
}