#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Xoa sach toan bo tai nguyen AWS do aws-setup.sh tao ra.
# Chay sau khi da nop bai va chup du screenshot, de khong phat sinh chi phi EC2.
#
#   bash infra/teardown.sh
# ---------------------------------------------------------------------------
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

BUCKET="mlops-lab-k3-${ACCOUNT_ID}"
CI_USER="mlops-lab-ci"
EC2_ROLE="mlops-lab-ec2-role"
INSTANCE_PROFILE="mlops-lab-ec2-profile"
SG_NAME="mlops-serve-sg"
KEY_NAME="mlops_deploy"
INSTANCE_NAME="mlops-serve"

say() { printf '\n=== %s ===\n' "$1"; }

say "1. Terminate EC2"
IDS=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=pending,running,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$IDS" ]; then
  aws ec2 terminate-instances --region "$REGION" --instance-ids $IDS >/dev/null
  echo "dang terminate: $IDS (cho toi khi xong de con xoa security group)"
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $IDS
else
  echo "khong co instance"
fi

say "2. Security group + key pair"
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
[ -n "$SG_ID" ] && [ "$SG_ID" != "None" ] && aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID"
aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME"

say "3. S3 bucket (xoa het object truoc)"
aws s3 rm "s3://$BUCKET" --recursive
aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"

say "4. IAM"
aws iam remove-role-from-instance-profile --instance-profile-name "$INSTANCE_PROFILE" --role-name "$EC2_ROLE"
aws iam delete-instance-profile --instance-profile-name "$INSTANCE_PROFILE"
aws iam delete-role-policy --role-name "$EC2_ROLE" --policy-name "mlops-lab-model-read"
aws iam delete-role --role-name "$EC2_ROLE"
for k in $(aws iam list-access-keys --user-name "$CI_USER" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  aws iam delete-access-key --user-name "$CI_USER" --access-key-id "$k"
done
aws iam delete-user-policy --user-name "$CI_USER" --policy-name "mlops-lab-bucket-rw"
aws iam delete-user --user-name "$CI_USER"

say "Xong. Nho xoa cac GitHub Secrets khong con dung."
