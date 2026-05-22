#!/bin/bash
# teardown.sh – Destroys ALL infrastructure
# Usage: ./scripts/teardown.sh
# WARNING: This deletes everything. Data is NOT recoverable.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ⚠  TEARDOWN WARNING ⚠                         ║"
echo "║  This will DESTROY all VMs, networking, and data.           ║"
echo "║  This action is IRREVERSIBLE.                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Type 'destroy' to confirm: " CONFIRM
[ "$CONFIRM" = "destroy" ] || { echo "Aborted."; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../terraform"

terraform destroy -auto-approve

echo -e "${GREEN}[✓] All infrastructure destroyed.${NC}"
echo "    Run ./scripts/deploy.sh to bring it back up."
