#!/bin/bash
# deploy.sh – Full stack deploy from scratch
# Usage: ./scripts/deploy.sh
# This is the single command that brings up the entire distributed inference stack.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Alchemyst AI – Distributed Inference Stack           ║"
echo "║               Full Deploy Script                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Preflight checks ──────────────────────────────────────────────────────────

log "Running preflight checks..."

command -v terraform >/dev/null 2>&1 || fail "terraform not found. Install it first."
command -v ansible-playbook >/dev/null 2>&1 || fail "ansible-playbook not found. Install it first."
command -v aws >/dev/null 2>&1 || fail "aws CLI not found. Install it first."

aws sts get-caller-identity >/dev/null 2>&1 || fail "AWS credentials not configured. Run: aws configure"

[ -f ~/.ssh/devops-intern ] || fail "SSH key not found at ~/.ssh/devops-intern. Run: ssh-keygen -t rsa -b 4096 -f ~/.ssh/devops-intern -N ''"

ok "All preflight checks passed"

# ── Step 1: Terraform ─────────────────────────────────────────────────────────

log "Step 1/4: Provisioning infrastructure with Terraform..."
cd "$ROOT/terraform"

terraform init -upgrade
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

ok "Infrastructure provisioned"

# ── Step 2: Generate Ansible inventory ───────────────────────────────────────

log "Step 2/4: Generating Ansible inventory from Terraform outputs..."
bash "$SCRIPT_DIR/generate_inventory.sh"
ok "Inventory generated"

# ── Step 3: Wait for VMs to be SSH-ready ─────────────────────────────────────

log "Step 3/4: Waiting for VMs to become available..."
GATEWAY_IP=$(terraform output -raw gateway_public_ip)

log "Waiting for gateway SSH (this takes ~60 seconds)..."
for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ~/.ssh/devops-intern ubuntu@"$GATEWAY_IP" "echo ok" 2>/dev/null; then
    ok "Gateway is reachable"
    break
  fi
  echo -n "."
  sleep 5
done

# ── Step 4: Ansible ──────────────────────────────────────────────────────────

log "Step 4/4: Configuring VMs with Ansible..."
cd "$ROOT/ansible"

# Ping all hosts first
ansible all -i inventory.ini -m ping --timeout=30

# Run full playbook
ansible-playbook -i inventory.ini site.yml -v

ok "All services deployed"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Deploy Complete! 🚀                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

cd "$ROOT/terraform"
API_ENDPOINT=$(terraform output -raw api_endpoint)

echo -e "${GREEN}API Endpoint:${NC} $API_ENDPOINT"
echo ""
echo -e "${GREEN}Test it:${NC}"
echo "  curl -X POST $API_ENDPOINT \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]}'"
echo ""
echo -e "${GREEN}SSH Access:${NC}"
terraform output ssh_gateway
echo ""
warn "COST REMINDER: Stop VMs when not in use to stay within free tier."
warn "Run: ./scripts/stop_vms.sh"
