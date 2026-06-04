# K8s on AWS — Terraform 1-Click Automation

Dự án này tự động hóa hoàn toàn việc triển khai một cụm Kubernetes thu nhỏ (sử dụng **Minikube**) chạy bên trong một máy ảo **AWS EC2**, sau đó triển khai một ứng dụng web Nginx đơn giản (chứa thông điệp custom) lên cụm K8s này và expose (công khai) nó ra ngoài Internet thông qua **Application Load Balancer (ALB)** của AWS.

Toàn bộ tài nguyên hạ tầng (VPC, Subnets, Security Groups, EC2, ALB) và tài nguyên phần mềm (K8s Deployment, K8s Service) đều được quản lý đồng nhất bằng **Terraform** trong một lần triển khai ("1-Click").

---

## 1. Sơ đồ Kiến trúc & Luồng Dữ liệu (Traffic Flow)

Luồng đi của dữ liệu từ người dùng ngoài Internet vào đến container chứa ứng dụng K8s:

```
User (Internet) 
   │
   ▼ (Port 80)
┌─────────────────────────────────────────────────────────┐
│ [AWS ALB] (Public Subnets)                              │
│ - Nhận traffic từ ngoài Internet                        │
│ - Định tuyến vào Target Group trỏ đến EC2 ở Port 30000  │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼ (Đẩy traffic vào Port 30000 của EC2)
┌─────────────────────────────────────────────────────────┐
│ [AWS EC2 Instance] (Public Subnet)                      │
│ - Chạy HDH Amazon Linux 2023 (t3.medium)                │
│ - Có mở SG Ingress cổng 22 (SSH), 8443 (API), 30000     │
│                                                         │
│   ┌─────────────────────────────────────────────────┐   │
│   │ [Docker Engine] (Mạng ảo cục bộ)                │   │
│   │                                                 │   │
│   │   ┌─────────────────────────────────────────┐   │   │
│   │   │ [Minikube Cluster]                      │   │   │
│   │   │ - Minikube IP: 192.168.49.2             │   │   │
│   │   │ - K8s API Port: 8443                    │   │   │
│   │   │                                         │   │   │
│   │   │   ┌─────────────────────────────────┐   │   │   │
│   │   │   │ [Pod: xbrain-web]               │   │   │   │
│   │   │   │ - Container: Nginx (Port 80)    │   │   │   │
│   │   │   └────────────────▲────────────────┘   │   │   │
│   │   │                    │                    │   │   │
│   │   │   ┌────────────────┴────────────────┐   │   │   │
│   │   │   │ [Service: xbrain-service]       │   │   │   │
│   │   │   │ - Type: NodePort (Port 30000)   │   │   │   │
│   │   │   └────────────────▲────────────────┘   │   │   │
│   │   └────────────────────┼────────────────────┘   │   │
│   └────────────────────────┼────────────────────────┘   │
│                            │ (Cầu nối chuyển tiếp mạng) │
│   [socat Port-Forward] ────┴──────────────────────────  │
│   - socat :8443   -->  MINIKUBE_IP:8443                 │
│   - socat :30000  -->  MINIKUBE_IP:30000                │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Tại sao code hiện tại giải quyết được bài toán này?

Đề bài này có một số thách thức kỹ thuật lớn ("cạm bẫy") mà code của chúng ta đã xử lý thành công:

### A. Vấn đề cô lập mạng (Network Isolation) & Giải pháp `socat`
- **Thách thức**: Minikube chạy bằng driver `docker` bên trong EC2. Điều này tạo ra một lớp mạng ảo cô lập (thường là dải `192.168.49.x`). Máy chủ EC2 và đặc biệt là AWS ALB không thể nhìn thấy hay gửi gói tin trực tiếp vào dải IP nội bộ này.
- **Giải pháp**: 
  - Sử dụng công cụ **`socat`** chạy nền (background daemon) trên EC2 làm cầu nối mạng (Port Forwarding).
  - Lệnh `socat TCP-LISTEN:30000,fork,bind=0.0.0.0 TCP:$MINIKUBE_IP:30000` sẽ lắng nghe tất cả kết nối đến cổng `30000` trên IP Public/Private của EC2 và chuyển tiếp thẳng vào cổng `30000` (NodePort K8s) bên trong Minikube.
  - Tương tự, cổng `8443` cũng được forward để Terraform trên máy tính của bạn có thể gọi API quản lý K8s.

### B. Vấn đề xác thực từ xa & Giải pháp tự động cấu hình Kubeconfig
- **Thách thức**: Minikube khởi tạo sẽ sinh chứng chỉ SSL và file cấu hình `kubeconfig` chứa các đường dẫn tuyệt đối local trên EC2 (như `/home/ec2-user/.minikube/...`). Nếu copy file này về máy tính cá nhân, Terraform sẽ không hiểu được các đường dẫn file key/cert đó trên Windows/macOS và báo lỗi.
- **Giải pháp**:
  - Dùng lệnh `kubectl config view --flatten` để gộp toàn bộ nội dung file chứng chỉ (cert & key) mã hóa dạng Base64 trực tiếp vào file cấu hình.
  - Sử dụng thuộc tính `triggers` trong `null_resource` liên kết với `aws_instance.name.id` để đảm bảo luôn kéo lại file config mới nếu EC2 bị thay đổi.
  - Sử dụng PowerShell (trên máy tính local) tự động Regex Replace dải IP nội bộ trong file config sang IP Public thực tế của EC2.

### C. Đồng bộ hóa tiến trình bootstrap (Race Condition)
- **Thách thức**: Khi EC2 được AWS chuyển trạng thái sang `Running`, Terraform sẽ coi như tài nguyên đã tạo xong và lập tức chạy K8s Provider để tạo Deployment. Nhưng thực tế lúc này EC2 mới đang khởi động và tải Docker/Minikube (mất 3-5 phút), dẫn đến crash do không tìm thấy cụm K8s.
- **Giải pháp**:
  - Tích hợp công cụ `cloud-init status --wait` trong phần `remote-exec` của `null_resource`. Lệnh này ép tiến trình Terraform local đứng đợi cho đến khi đoạn script cài đặt `user_data` trên EC2 chạy xong hoàn toàn 100%.

---

## 3. Hướng dẫn sử dụng & Triển khai (Deploy)

Vì dự án có sự phụ thuộc chéo giữa AWS Provider (tạo hạ tầng) và Kubernetes Provider (triển khai ứng dụng dựa trên file `kubeconfig.yaml` chưa được tạo), chúng ta áp dụng chiến thuật **Triển khai 2 nhịp (Targeted Apply)** để tự động hóa 100%:

### Bước 1: Chuẩn bị file biến cấu hình
1. Tạo một bản sao từ file ví dụ:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Mở file `terraform.tfvars` lên và cập nhật các thông số cần thiết phù hợp với tài khoản AWS của bạn (ví dụ: region, AZs, IP allowed cho SSH).

### Bước 2: Nhịp 1 - Khởi tạo hạ tầng AWS & Lấy file cấu hình Kubeconfig
Chạy lệnh apply chỉ nhắm mục tiêu vào các tài nguyên hạ tầng cốt lõi và tiến trình kéo file config:
```bash
terraform init
terraform apply -target="module.aws_vpc" -target="module.aws_ec2" -target="null_resource.fetch_and_patch_kubeconfig" -target="module.alb"
```
*Gõ `yes` khi được hỏi. Quá trình này sẽ mất khoảng 4-5 phút vì Terraform phải SSH vào EC2 và đợi Minikube cài đặt xong hoàn toàn trước khi tải file `kubeconfig.yaml` về.*

### Bước 3: Nhịp 2 - Triển khai ứng dụng Web Nginx lên K8s
Sau khi Nhịp 1 chạy xong, file `kubeconfig.yaml` đã nằm ngay ngắn ở thư mục dự án trên máy bạn. Bây giờ bạn chỉ cần chạy lệnh apply toàn bộ để K8s Provider bắt tay triển khai:
```bash
terraform apply
```
*Gõ `yes`. Lệnh này sẽ hoàn thành rất nhanh trong vòng vài giây.*

### Bước 4: Kiểm tra kết quả
Khi quá trình triển khai thành công, Terraform sẽ xuất ra URL truy cập:
```text
Outputs:
app_url = "http://k8s-lab-alb-XXXXXX.ap-southeast-1.elb.amazonaws.com"
```
Hãy copy đường dẫn này, dán lên trình duyệt và chờ khoảng 1-2 phút (để ALB hoàn thành Health Check). Bạn sẽ thấy dòng chữ:
> **Hello Xbrain! 1-Click Automation Works!**

---

## 4. Hướng dẫn Dọn dẹp & Xóa tài nguyên (Destroy)

Để tránh phát sinh chi phí trên AWS, khi học tập/kiểm tra xong, bạn hãy tiến hành xóa sạch tài nguyên bằng lệnh sau:

```bash
terraform destroy
```
*Gõ `yes` và xác nhận. Terraform sẽ tự động gỡ bỏ Pod/Service K8s trước, sau đó xóa ALB, EC2, KeyPair, Security Groups và VPC một cách an toàn.*

Sau khi xóa xong, bạn có thể xóa thủ công file `kubeconfig.yaml` và `lab-key.pem` được tạo ra trên máy tính cá nhân để giữ thư mục làm việc sạch sẽ.
