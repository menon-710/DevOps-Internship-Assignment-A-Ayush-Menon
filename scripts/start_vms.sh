#!/bin/bash
# start_vms.sh – Starts all EC2 instances
# Usage: ./scripts/start_vms.sh

set -euo pipefail

REGION="ap-south-1"
PROJECT="alchemyst-inference"

echo "[*] Finding all $PROJECT instances..."

INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=stopped" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "[!] No stopped instances found."
  exit 0
fi

echo "[*] Starting: $INSTANCE_IDS"
aws ec2 start-instances --region "$REGION" --instance-ids $INSTANCE_IDS

echo "[*] Waiting for instances to be running..."
aws ec2 wait instance-running --region "$REGION" --instance-ids $INSTANCE_IDS

echo "[✓] Instances started."
echo ""
echo "Note: After starting, wait ~30 seconds then check the API:"
GATEWAY_IP=$(cd "$(dirname "$0")/../terraform" && terraform output -raw gateway_public_ip 2>/dev/null || echo "<gateway-ip>")
echo "  curl http://$GATEWAY_IP/health"
