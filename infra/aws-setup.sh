#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Dung toan bo ha tang AWS cho lab MLOps Day 21.
#
#   - S3 bucket            : luu DVC remote + model artifact
#   - IAM user mlops-lab-ci: danh tinh cho GitHub Actions (quyen toi thieu)
#   - IAM role  mlops-lab-ec2-role : danh tinh cho EC2 doc model (chi doc)
#   - Security group       : mo 22 va 8000 (SSH chi xac thuc bang key)
#   - EC2 t3.micro Ubuntu 22.04 : chay FastAPI inference server
#
# Script idempotent: chay lai nhieu lan khong tao trung tai nguyen.
# Ket qua (gia tri cho GitHub Secrets) duoc ghi ra infra/secrets.txt (da gitignore).
#
# Yeu cau: aws CLI da cau hinh, ssh-keygen, jq khong bat buoc.
# ---------------------------------------------------------------------------
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

BUCKET="mlops-lab-k3-${ACCOUNT_ID}"
CI_USER="mlops-lab-ci"
EC2_ROLE="mlops-lab-ec2-role"
INSTANCE_PROFILE="mlops-lab-ec2-profile"
SG_NAME="mlops-serve-sg"
KEY_NAME="mlops_deploy"
KEY_FILE="$HOME/.ssh/mlops_deploy"
# aws.exe ban Windows khong hieu duong dan kieu Git Bash (/c/Users/...),
# nen can duong dan Windows khi truyen qua fileb://
winpath() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || printf %s "$1"; }
INSTANCE_NAME="mlops-serve"
AMI_ID="$(aws ec2 describe-images --owners 099720109477 --region "$REGION" \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' \
            'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"

OUT="$(dirname "$0")/secrets.txt"

say() { printf '\n=== %s ===\n' "$1"; }

# ---------------------------------------------------------------------------
say "1. S3 bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "bucket da ton tai, bo qua"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  echo "da tao"
fi

# ---------------------------------------------------------------------------
say "2. IAM user cho CI: $CI_USER"
# Quyen toi thieu: chi doc/ghi/xoa object BEN TRONG bucket nay, khong duoc xoa bucket.
# Hai action *ObjectTagging la bat buoc cho buoc promote candidate -> latest:
# `aws s3 cp` giua hai key S3 la copy phia server va luon doc/ghi tag cua object.
CI_POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::${BUCKET}" },
    { "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "s3:GetObjectTagging", "s3:PutObjectTagging"
      ],
      "Resource": "arn:aws:s3:::${BUCKET}/*" }
  ]
}
JSON
)
aws iam get-user --user-name "$CI_USER" >/dev/null 2>&1 || aws iam create-user --user-name "$CI_USER" >/dev/null
aws iam put-user-policy --user-name "$CI_USER" \
  --policy-name "mlops-lab-bucket-rw" --policy-document "$CI_POLICY"

# Chi tao access key khi user chua co key nao (moi user toi da 2 key).
EXISTING_KEYS=$(aws iam list-access-keys --user-name "$CI_USER" \
  --query 'length(AccessKeyMetadata)' --output text)
if [ "$EXISTING_KEYS" = "0" ]; then
  CI_KEY_JSON=$(aws iam create-access-key --user-name "$CI_USER")
  CI_AK=$(echo "$CI_KEY_JSON" | python -c "import sys,json;print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
  CI_SK=$(echo "$CI_KEY_JSON" | python -c "import sys,json;print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")
  echo "da tao access key moi"
else
  # AWS khong cho doc lai secret key da tao. Neu lan chay truoc da ghi key that vao
  # secrets.txt thi giu nguyen gia tri do, tuyet doi khong ghi de bang placeholder -
  # lam vay se pha mat credentials duy nhat ban dang co.
  CI_AK=""; CI_SK=""
  if [ -f "$OUT" ]; then
    PREV_LINE=$(grep -A1 '^CLOUD_CREDENTIALS$' "$OUT" | tail -1)
    case "$PREV_LINE" in
      *AKIA*)
        CI_AK=$(printf %s "$PREV_LINE" | python -c "import sys,json;print(json.load(sys.stdin)['aws_access_key_id'])")
        CI_SK=$(printf %s "$PREV_LINE" | python -c "import sys,json;print(json.load(sys.stdin)['aws_secret_access_key'])")
        echo "giu lai access key da ghi o lan chay truoc"
        ;;
    esac
  fi
  if [ -z "$CI_AK" ]; then
    CI_AK="<da ton tai nhung khong doc lai duoc>"
    CI_SK="<xoa key cu roi chay lai script: aws iam delete-access-key ...>"
  fi
  echo "user da co $EXISTING_KEYS access key, khong tao them"
fi

# ---------------------------------------------------------------------------
say "3. IAM role cho EC2: $EC2_ROLE"
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
EC2_POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET}/models/latest/*" }
  ]
}
JSON
)
aws iam get-role --role-name "$EC2_ROLE" >/dev/null 2>&1 || \
  aws iam create-role --role-name "$EC2_ROLE" --assume-role-policy-document "$TRUST" >/dev/null
aws iam put-role-policy --role-name "$EC2_ROLE" \
  --policy-name "mlops-lab-model-read" --policy-document "$EC2_POLICY"
aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE" >/dev/null 2>&1 || {
  aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$INSTANCE_PROFILE" --role-name "$EC2_ROLE"
  echo "cho IAM propagate 10s..."; sleep 10
}

# ---------------------------------------------------------------------------
say "4. SSH key pair: $KEY_NAME"
if [ ! -f "$KEY_FILE" ]; then
  ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "github-actions-deploy"
fi
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
  aws ec2 import-key-pair --key-name "$KEY_NAME" --region "$REGION" \
    --public-key-material "fileb://$(winpath "${KEY_FILE}.pub")" >/dev/null
  echo "da import public key len AWS"
fi

# ---------------------------------------------------------------------------
say "5. Security group: $SG_NAME"
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
  SG_ID=$(aws ec2 create-security-group --region "$REGION" --group-name "$SG_NAME" \
    --description "MLOps lab inference server" --query GroupId --output text)
fi
# Cong 22 phai mo public: job Deploy SSH vao VM tu GitHub-hosted runner, ma runner
# khong co dai IP co dinh - https://api.github.com/meta liet ke hang nghin CIDR, vuot
# xa gioi han 60 rule cua mot security group. Bu lai VM chi chap nhan xac thuc bang
# key: AMI Ubuntu dat san `passwordauthentication no`, va authorized_keys chi chua
# dung mot key ed25519 (mlops_deploy).
# Cong 8000 mo public de cham diem bang curl tu ngoai.
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 2>/dev/null || echo "rule 22 da co"
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
  --protocol tcp --port 8000 --cidr 0.0.0.0/0 2>/dev/null || echo "rule 8000 da co"
echo "SG_ID=$SG_ID"

# ---------------------------------------------------------------------------
say "6. EC2 instance: $INSTANCE_NAME"
INSTANCE_ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "None")
if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
  INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI_ID" --instance-type t3.micro --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile "Name=$INSTANCE_PROFILE" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query 'Instances[0].InstanceId' --output text)
  echo "da tao $INSTANCE_ID, cho running..."
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
fi
VM_HOST=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# ---------------------------------------------------------------------------
say "7. Gia tri cho GitHub Secrets -> $OUT"
cat > "$OUT" <<TXT
# GitHub repo > Settings > Secrets and variables > Actions > New repository secret
# KHONG commit file nay (da nam trong .gitignore).

CLOUD_CREDENTIALS
{"aws_access_key_id":"${CI_AK}","aws_secret_access_key":"${CI_SK}"}

CLOUD_BUCKET
${BUCKET}

VM_HOST
${VM_HOST}

VM_USER
ubuntu

VM_SSH_KEY
$(cat "$KEY_FILE")

# --- tham chieu ---
# region        : ${REGION}
# instance id   : ${INSTANCE_ID}
# security group: ${SG_ID}
# ami           : ${AMI_ID}
TXT
echo "xong. Xem $OUT"
