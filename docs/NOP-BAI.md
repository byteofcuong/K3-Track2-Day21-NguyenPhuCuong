# Checklist nộp bài - Day 21

Theo mục "Hướng dẫn nộp bài" trong [README.md](../README.md).

## 1. URL repo GitHub công khai

https://github.com/byteofcuong/K3-Track2-Day21-NguyenPhuCuong

## 2. Chuỗi ảnh chụp màn hình (lưu vào `docs/screenshots/`)

| # | Ảnh cần chụp | Tên file gợi ý | Cách lấy |
|---|---|---|---|
| 1 | MLflow UI hiển thị ≥ 3 thí nghiệm | `01-mlflow-runs.png` | `mlflow ui --backend-store-uri sqlite:///mlflow.db` → http://localhost:5000 → mở experiment `wine-quality`, sort theo `accuracy` giảm dần |
| 2 | MLflow Compare nhiều run | `02-mlflow-compare.png` | Chọn nhiều run → nút **Compare** |
| 3 | Actions: 4 jobs xanh (Bước 2) | `03-actions-buoc2.png` | Tab Actions → lần chạy của commit code |
| 4 | Actions: Eval đỏ, Deploy bị skip | `04-actions-eval-gate.png` | Lần chạy demo ngưỡng (T10) |
| 5 | Actions: 4 jobs xanh (Bước 3) | `05-actions-buoc3.png` | Lần chạy do commit dữ liệu kích hoạt — kiểm tra tên run là commit message dữ liệu |
| 6 | Kết quả `curl /health` và `curl /predict` | `06-curl.png` | Chụp cả terminal, thấy rõ IP VM |
| 7 | S3 Console: prefix `dvc/` | `07-s3-dvc.png` | Console → bucket `mlops-lab-k3-784917519973` → `dvc/` |
| 8 | S3 Console: `models/latest/model.pkl` | `08-s3-model.png` | Cùng bucket → `models/latest/` |

## 3. File báo cáo

[BAOCAO.md](../BAOCAO.md) — không quá 1 trang A4.

## Lệnh kiểm tra nhanh

```bash
VM_IP=44.222.163.244

curl http://$VM_IP:8000/health
curl -X POST http://$VM_IP:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [7.4, 0.70, 0.00, 1.9, 0.076, 11.0, 34.0, 0.9978, 3.51, 0.56, 9.4, 0]}'
```

## Sau khi nộp xong

```bash
bash infra/teardown.sh     # xoá EC2 + S3 + IAM để không phát sinh chi phí
```
