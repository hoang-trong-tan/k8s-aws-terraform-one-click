terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3.0"
    }
    local = {
      source = "hashicorp/local"
    }
    null = {
      source = "hashicorp/null"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

provider "tls" {

}

provider "local" {

}

/*
provider "kubernetes" {
  config_path = "${path.module}/kubeconfig.yaml"
}
*/

provider "kubernetes" {
    host                   = yamldecode(data.local_file.kubeconfig.content).clusters[0].cluster.server
    client_certificate     = base64decode(yamldecode(data.local_file.kubeconfig.content).users[0].user.client-certificate-data)
    client_key             = base64decode(yamldecode(data.local_file.kubeconfig.content).users[0].user.client-key-data)
    cluster_ca_certificate = base64decode(yamldecode(data.local_file.kubeconfig.content).clusters[0].cluster.certificate-authority-data)
  }

data "local_file" "kubeconfig" {
  filename   = "${path.module}/kubeconfig.yaml"
  depends_on = [null_resource.fetch_and_patch_kubeconfig]
}




# 3. K8s Resource: Tạo Deployment Nginx và sửa file index chứa chữ "Hello Xbrain"
resource "kubernetes_deployment_v1" "nginx_app" {
  # ÉP BUỘC: Phải đợi null_resource chạy xong và có file config thì mới thực hiện block này
  depends_on = [null_resource.fetch_and_patch_kubeconfig]
  
  metadata {
    name = "xbrain-web"
    labels = {
      app = "nginx"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        # Dùng một container init chạy trước để tạo file HTML có chữ Hello Xbrain
        init_container {
          name    = "install"
          image   = "busybox:latest"
          command = ["sh", "-c", "echo '<h1>Hello Xbrain! 1-Click Automation Works!</h1>' > /usr/share/nginx/html/index.html"]

          volume_mount {
            name       = "web-content"
            mount_path = "/usr/share/nginx/html"
          }
        }

        container {
          name  = "nginx-container"
          image = "nginx:alpine"

          port {
            container_port = 80
          }

          volume_mount {
            name       = "web-content"
            mount_path = "/usr/share/nginx/html"
          }
        }

        volume {
          name = "web-content"
          empty_dir {}
        }
      }
    }
  }
}



resource "kubernetes_service_v1" "nginx_service" {
  depends_on = [null_resource.fetch_and_patch_kubeconfig, kubernetes_deployment_v1.nginx_app]

  metadata {
    name = "xbrain-service"
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
      node_port   = 30000 # Khớp chính xác với cấu hình Target Group của ALB
    }

    type = "NodePort"
  }
}

# 5. Output đường dẫn cuối cùng để bạn test kết quả
output "app_url" {
  value       = "http://${module.alb.alb_dns_name}"
  description = "Gõ đường dẫn này lên trình duyệt sau khi apply thành công"
}


resource "tls_private_key" "k8s_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s_keypair" {
  key_name   = "k8s-lab-key"
  public_key = tls_private_key.k8s_key.public_key_openssh
}

# 3. Lưu Private Key về thư mục code hiện tại để lát nữa thò tay vào EC2
resource "local_file" "private_key" {
  content         = tls_private_key.k8s_key.private_key_pem
  filename        = "${path.module}/lab-key.pem"
  file_permission = "0400" # Phân quyền bảo mật: Chỉ cho phép đọc
}

module "aws_vpc" {
  source      = "./module/vpc"
  cidr_vpc    = var.cidr_vpc
  cidr_subnet = var.cidr_subnet
  tag_subnet  = var.tag_subnet
  tags_vpc    = var.tags_vpc
  tags_igw    = var.tags_igw
  tags_rt     = var.tags_rt
  name_sg_ec2 = var.name_sg_ec2
  name_sg_alb = var.name_sg_alb
}

module "aws_ec2" {
  source            = "./module/ec2"
  subnet_id_for_ec2 = module.aws_vpc.aws_subnet["public_subnet_2"].id
  sg_id_for_ec2     = module.aws_vpc.aws_sg_ec2
  tags_ec2          = var.tags_ec2
  key_name          = aws_key_pair.k8s_keypair.key_name
}



resource "null_resource" "fetch_and_patch_kubeconfig" {
  triggers = {
    ec2_instance_id = module.aws_ec2.instance_id
  }

  depends_on = [module.aws_ec2, local_file.private_key]
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.k8s_key.private_key_pem
    host        = module.aws_ec2.public_ip
  }

  # action 1 : wait inside ec2
  provisioner "remote-exec" {
    inline = [
      "echo 'đang chờ hệ điều hành chạy xong user data..'",
      # Lệnh cloud-init status --wait sẽ ép Terraform đứng im 
      # cho đến khi kịch bản bash script tải Docker/Minikube chạy xong 100%
      "cloud-init status --wait",
      "echo 'Kiểm tra xem file kubeconfig đã có chưa...'",
      "ls -l /home/ec2-user/.kube/config",
      "kubectl config view --flatten > /home/ec2-user/kubeconfig-flat.yaml"

    ]
  }
/*
  provisioner "local-exec" {
    command     = "icacls ${local_file.private_key.filename} /inheritance:r /grant:r \"$($env:USERNAME):(R)\""
    interpreter = ["PowerShell", "-Command"]
  }
*/
  provisioner "local-exec" {
    command = "chmod 400 ${local_file.private_key.filename}"
  }

  # --- HÀNH ĐỘNG 2: KÉO FILE VỀ (Chạy trên Laptop của bạn) ---
  provisioner "local-exec" {
      # Chú ý đường dẫn file nguồn đã được đổi thành kubeconfig-flat.yaml
      command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${local_file.private_key.filename} ec2-user@${module.aws_ec2.public_ip}:/home/ec2-user/kubeconfig-flat.yaml ${path.module}/kubeconfig.yaml"
    }

  # --- HÀNH ĐỘNG 3: SỬA IP (Chạy trên Laptop của bạn) ---
  # Dùng PowerShell để đọc file, tìm chuỗi "127.0.0.1" và thay bằng Public IP, sau đó lưu lại
  /*
  provisioner "local-exec" {
      command     = "(Get-Content ${path.module}/kubeconfig.yaml) -replace 'https://[0-9\\.]+:8443', 'https://${module.aws_ec2.public_ip}:8443' | Set-Content ${path.module}/kubeconfig.yaml"
      interpreter = ["PowerShell", "-Command"]
    }
*/
# --- HÀNH ĐỘNG 3: SỬA IP (Chạy trên máy Linux của bạn) ---
  provisioner "local-exec" {
    command = "sed -i 's|https://[0-9\\.]\\+:8443|https://${module.aws_ec2.public_ip}:8443|g' ${path.module}/kubeconfig.yaml"
  }  
}



module "alb" {
  source      = "./module/alb"
  vpc_id      = module.aws_vpc.vpc_id_demo
  instance_id = module.aws_ec2.instance_id

  public_subnet_ids = [
    module.aws_vpc.aws_subnet["public_subnet_1"].id,
    module.aws_vpc.aws_subnet["public_subnet_2"].id
  ]
  alb_sg = module.aws_vpc.aws_sg_alb
}
