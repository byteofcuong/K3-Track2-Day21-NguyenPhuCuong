#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Cau hinh EC2 de chay FastAPI inference server (thuc hien mot lan).
#
#   - cai dat thu vien Python DUNG PHIEN BAN voi CI runner
#   - copy src/serve.py len VM
#   - tao systemd service mlops-serve (tu khoi dong lai khi VM reboot)
#
# Chay tu may ca nhan:  bash infra/vm-setup.sh
# ---------------------------------------------------------------------------
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="mlops-lab-k3-${ACCOUNT_ID}"
KEY_FILE="$HOME/.ssh/mlops_deploy"
VM_USER="ubuntu"

VM_HOST=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=mlops-serve" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@$VM_HOST"

echo "=== VM: $VM_HOST | bucket: $BUCKET ==="

echo "=== 1. Cai dat thu vien ==="
# Phien ban scikit-learn / numpy phai TRUNG voi CI runner. Model duoc pickle boi
# scikit-learn 1.4.2 + numpy 1.26.4; joblib.load bang phien ban khac se loi hoac
# cho ket qua sai lech.
$SSH bash -s <<'REMOTE'
set -e
sudo apt-get update -qq
sudo apt-get install -y -qq python3-pip
pip3 install --quiet --upgrade pip
pip3 install --quiet \
  fastapi==0.111.0 uvicorn==0.29.0 \
  scikit-learn==1.4.2 numpy==1.26.4 scipy==1.13.1 \
  joblib==1.4.2 boto3
mkdir -p ~/models ~/src
echo "da cai xong"
REMOTE

echo "=== 2. Copy serve.py ==="
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  src/serve.py "$VM_USER@$VM_HOST:~/src/serve.py"

echo "=== 3. Tao systemd service ==="
# Khong co GOOGLE_APPLICATION_CREDENTIALS hay file key nao: boto3 lay credentials
# tam thoi tu IAM instance profile qua instance metadata.
$SSH "sudo tee /etc/systemd/system/mlops-serve.service > /dev/null" <<EOF
[Unit]
Description=MLOps Model Inference Server
After=network.target

[Service]
User=$VM_USER
WorkingDirectory=/home/$VM_USER
Environment="S3_BUCKET=$BUCKET"
Environment="AWS_DEFAULT_REGION=$REGION"
ExecStart=/usr/bin/python3 /home/$VM_USER/src/serve.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

$SSH "sudo systemctl daemon-reload && sudo systemctl enable mlops-serve"

echo ""
echo "=== Xong ==="
echo "Chua start service: model chua co tren S3 cho den khi pipeline CI/CD chay lan dau."
echo "Sau khi pipeline chay xong:"
echo "  ssh -i $KEY_FILE $VM_USER@$VM_HOST 'sudo systemctl start mlops-serve'"
echo "  curl http://$VM_HOST:8000/health"
