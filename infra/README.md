# Hạ tầng AWS cho lab

Lab gốc lấy GCP làm ví dụ mặc định. Bài này dùng **AWS**, theo đúng bảng ánh xạ ở
[tasks/buoc-2.md](../tasks/buoc-2.md) mục "Lựa Chọn Cloud Provider".

| Khái niệm trong lab | Bản GCP (mặc định) | Bản dùng ở đây (AWS) |
|---|---|---|
| Object Storage | Google Cloud Storage | Amazon S3 |
| VM | Compute Engine | EC2 |
| DVC storage extra | `dvc[gs]` | `dvc[s3]` |
| Cloud SDK Python | `google-cloud-storage` | `boto3` |
| Credentials cho CI | Service Account JSON | IAM user access key |
| Credentials cho VM | copy `sa-key.json` lên VM | **IAM instance profile** (không có key nào nằm trên VM) |

## Tài nguyên được tạo

| Tài nguyên | Tên | Vai trò |
|---|---|---|
| S3 bucket | `mlops-lab-k3-<account-id>` | DVC remote (`dvc/`) + model artifact (`models/latest/`) |
| IAM user | `mlops-lab-ci` | Danh tính của GitHub Actions |
| IAM role + instance profile | `mlops-lab-ec2-role` / `mlops-lab-ec2-profile` | Danh tính của EC2 |
| Security group | `mlops-serve-sg` | Mở `22` (chỉ IP của bạn) và `8000` (public) |
| EC2 | `mlops-serve`, t3.micro, Ubuntu 22.04 | Chạy FastAPI inference server |
| Key pair | `mlops_deploy` (ed25519) | GitHub Actions SSH vào VM để deploy |

## Quyền tối thiểu

Lab nhấn mạnh nguyên tắc quyền tối thiểu (`tasks/buoc-2.md` mục 2.2: dùng `objectAdmin`, **không** dùng
`storage.admin`). Bản AWS áp dụng tương đương và chặt hơn một bậc:

- `mlops-lab-ci` chỉ có `GetObject` / `PutObject` / `DeleteObject` **bên trong** bucket, cộng `ListBucket`.
  Không có quyền xoá bucket, không đụng được tài nguyên nào khác trong account.
- `mlops-lab-ec2-role` chỉ có `GetObject` trên đúng prefix `models/latest/*` — VM chỉ cần đọc model,
  không cần ghi và không cần thấy dữ liệu huấn luyện.
- VM **không giữ file credentials nào**. Bản GCP của lab yêu cầu `scp sa-key.json` lên VM; instance profile
  của AWS cấp credentials tạm thời qua instance metadata nên bỏ được bước đó, và không có key nào để rò rỉ.

## Cách dùng

```bash
bash infra/aws-setup.sh     # tạo hạ tầng, ghi giá trị secrets ra infra/secrets.txt
bash infra/vm-setup.sh      # cài đặt và cấu hình service trên EC2
bash infra/teardown.sh      # xoá sạch sau khi nộp bài
```

`aws-setup.sh` idempotent — chạy lại nhiều lần không tạo trùng tài nguyên.

`infra/secrets.txt` chứa access key và SSH private key nên **đã nằm trong `.gitignore`**, không bao giờ
được commit. Nếu chạy lại script khi IAM user đã có access key, script sẽ không tạo key mới (AWS không cho
đọc lại secret key cũ) — muốn lấy key mới thì xoá key cũ rồi chạy lại:

```bash
aws iam list-access-keys --user-name mlops-lab-ci
aws iam delete-access-key --user-name mlops-lab-ci --access-key-id <KEY_ID>
bash infra/aws-setup.sh
```

## Chi phí

t3.micro ở us-east-1 khoảng **$0.0104/giờ** (~$7.5/tháng nếu chạy liên tục); free tier 12 tháng đầu phủ
750 giờ/tháng t3.micro. S3 ở mức dữ liệu của lab (~1 MB) gần như bằng 0. Chạy `teardown.sh` ngay sau khi
chụp xong screenshot để không phát sinh thêm.
