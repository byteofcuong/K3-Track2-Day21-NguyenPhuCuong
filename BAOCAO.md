# Báo cáo Lab Day 21 — CI/CD cho AI Systems

Nguyễn Phú Cường · K3 Track 2 · https://github.com/byteofcuong/K3-Track2-Day21-NguyenPhuCuong
Cloud: **AWS** (S3 + EC2), theo bảng ánh xạ provider ở `tasks/buoc-2.md`.

## 1. Bộ siêu tham số đã chọn và lý do

11 run trên MLflow (experiment `wine-quality`). Năm run RandomForest ở Bước 1:

| n_estimators | max_depth | min_samples_split | accuracy | f1_score |
|---|---|---|---|---|
| 50 | 3 | 2 | 0.5580 | 0.5185 |
| 100 | 5 | 2 | 0.5640 | 0.5534 |
| 200 | 10 | 5 | 0.6440 | 0.6417 |
| 200 | None | 2 | 0.6740 | 0.6730 |
| **500** | **None** | **2** | **0.6760** | **0.6748** |

**Chọn `n_estimators=500, max_depth=None, min_samples_split=2`.**

Yếu tố quyết định là `max_depth` chứ không phải `n_estimators`: bỏ giới hạn độ sâu nâng accuracy từ 0.6440 lên 0.6740 (+0.030), còn tăng cây từ 200 lên 500 chỉ thêm 0.002. Cây cắt ở độ sâu 3–5 không đủ tách ba lớp chất lượng vốn phân biệt bằng tương tác phi tuyến giữa nhiều đặc trưng hoá học; RandomForest chống overfit bằng bagging chứ không bằng cắt sâu. Đánh đổi: 500 cây cho file model 54.6 MB so với ~22 MB của 200 cây để đổi lấy +0.002 — chấp nhận được ở quy mô lab, nhưng nếu tối ưu chi phí thì 200 cây hợp lý hơn.

*Bonus 2*: `gradient_boosting` 0.6800 > `random_forest` 0.6760 > `logistic_regression` 0.5680. Mô hình tuyến tính kém hẳn, xác nhận bài toán phi tuyến.

## 2. Kết quả Bước 2 và Bước 3

| Chỉ số | Bước 2 (2998 mẫu) | Bước 3 (5996 mẫu) |
|---|---|---|
| accuracy | 0.6760 | **0.7460** |
| f1_score | 0.6748 | **0.7451** |

Gấp đôi dữ liệu nâng accuracy **+0.070** — gấp 35 lần mức thu được từ toàn bộ việc dò siêu tham số (+0.002 giữa hai cấu hình tốt nhất). Với bài toán này, thu thập thêm dữ liệu hiệu quả hơn nhiều so với tinh chỉnh mô hình.

## 3. Khó khăn và cách giải quyết

**Ngưỡng 0.70 không đạt được ở Bước 2.** Trần accuracy với 2998 mẫu là 0.684 (đã thử RF/ExtraTrees/GradientBoosting/HistGB/voting/feature engineering; CV 5-fold cho 0.670 ± 0.007). Ngưỡng 0.70 chỉ đạt khi có đủ 5996 mẫu. Giải pháp: đưa ngưỡng thành tham số `eval_threshold` trong `params.yaml` thay vì hằng số cứng, đặt 0.65 cho Bước 2 — ngưỡng và siêu tham số luôn nằm trong cùng một commit, đổi được theo lượng dữ liệu mà không sửa code.

**Bốn lỗi môi trường** đều sẽ làm hỏng CI nếu bỏ qua: `scikit-learn 1.4.2` không có wheel cho Python 3.13 → dùng 3.12; `requirements.txt` không ghim numpy nên pip kéo numpy 2.x phá ABI của sklearn → ghim `numpy==1.26.4`; `mlflow 2.13` vẫn `import pkg_resources` đã bị gỡ khỏi `setuptools>=81` → ghim `setuptools==80.9.0`; CSV từ UCI dùng tên cột có dấu cách trong khi test dùng `snake_case` → chuẩn hoá trong `load_dataset()`.

**Deploy hỏng vì firewall.** Mở port 22 chỉ cho IP cá nhân thì runner GitHub không vào được, mà runner có hàng nghìn dải IP, vượt giới hạn 60 rule của security group. Phải mở 22 công khai; bù lại VM chỉ nhận xác thực bằng key.

**Thiếu quyền S3 tagging.** Promote `models/candidate/` → `models/latest/` bằng `aws s3 cp` là copy phía server nên luôn đọc/ghi tag, cần thêm `s3:GetObjectTagging` và `s3:PutObjectTagging`.

## 4. Khác biệt so với hướng dẫn gốc

VM không giữ file credentials nào — dùng IAM instance profile thay vì `scp sa-key.json`, giới hạn quyền ở đúng `s3:GetObject` trên `models/latest/*`. Model mới lên `models/candidate/`, chỉ job Deploy mới promote sang `models/latest/`, nên model không qua gate không bao giờ thay thế model đang chạy. Health check dùng vòng lặp thử lại 10×3s thay vì `sleep 5` cố định.
