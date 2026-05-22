#!/bin/bash
# stop_vms.sh – Stops all EC2 instances to save free-tier hours
# Usage: ./scripts/stop_vms.sh

set -euo pipefail

REGION="ap-south-1"
PROJECT="alchemyst-inference"

echo "[*] Finding all $PROJECT instances..."

INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "[!] No running instances found."
  exit 0
fi

echo "[*] Stopping: $INSTANCE_IDS"
aws ec2 stop-instances --region "$REGION" --instance-ids $INSTANCE_IDS

echo "[✓] Instances stopped. Run ./scripts/start_vms.sh to bring them back."
