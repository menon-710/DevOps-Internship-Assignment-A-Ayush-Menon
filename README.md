# Alchemyst DevOps Internship Assignment

Distributed RPC system deploying the `iii quickstart` project across multiple VMs on AWS, with workers communicating over a private subnet and inference exposed through a public JSON HTTP API.

---

## Architecture

```
                        Internet
                            │
                            ▼
                ┌───────────────────────┐
                │   VM-1: Gateway       │  ← PUBLIC
                │   3.108.103.134:80    │
                │   nginx reverse proxy │
                └───────────┬───────────┘
                            │
              ══════════════╪══════════════
              Private Subnet 10.0.1.0/24
              ══════════════╪══════════════
                            │
                            ▼
                ┌───────────────────────┐
                │   VM-2: iii Engine    │  ← PRIVATE (10.0.1.10)
                │   WebSocket :49134    │
                │   HTTP API   :3111    │
                └─────────┬─────┬──────┘
                          │     │
              ┌───────────┘     └──────────┐
              │   RPC over private subnet  │
              ▼                            ▼
  ┌──────────────────────┐    ┌──────────────────────┐
  │  VM-3: Caller Worker │    │  VM-4: Math Worker   │
  │  TypeScript          │───▶│  Python              │
  │  10.0.1.20           │    │  10.0.1.30           │
  └──────────────────────┘    └──────────────────────┘
```

### Request Flow

```
curl POST /math/add-two-numbers
  → nginx (VM-1, public)
  → iii engine REST :3111 (VM-2, private)
  → caller-worker TypeScript (VM-3, private)
  → math-worker Python via RPC (VM-4, private)
  → {"c": 30}
```

---

## Infrastructure

| Component | Cloud | Region | Instance |
|---|---|---|---|
| Gateway | AWS EC2 | ap-south-1 | t2.micro |
| iii Engine | AWS EC2 | ap-south-1 | t2.micro |
| Caller Worker | AWS EC2 | ap-south-1 | t2.micro |
| Math Worker | AWS EC2 | ap-south-1 | t2.micro |

**Networking:**
- VPC CIDR: `10.0.0.0/16`
- Public subnet: `10.0.0.0/24` (gateway only)
- Private subnet: `10.0.1.0/24` (engine + workers)
- NAT Gateway for outbound internet from private subnet (apt/pip installs)

**Security Groups:**
- Gateway: inbound 80/443 from `0.0.0.0/0`, SSH from your IP only
- Engine: inbound 49134 + 3111 from private subnet only
- Workers: no inbound, outbound to engine only

---

## API Reference

**Base URL:** `http://3.108.103.134`

### Health Check

```bash
curl http://3.108.103.134/health
```

**Response:**
```json
{"status": "ok", "service": "alchemyst-gateway"}
```

### Add Two Numbers

Triggers the full RPC chain: gateway → engine → caller-worker (TypeScript) → math-worker (Python)

```bash
curl -X POST http://3.108.103.134/math/add-two-numbers \
  -H "Content-Type: application/json" \
  -d '{"a": 10, "b": 20}'
```

**Request body:**
```json
{
  "a": 10,
  "b": 20
}
```

**Response:**
```json
{
  "c": 30,
  "success": "You've connected two workers and they're interoperating seamlessly."
}
```

---

## Worker Logs (Live Trace)

When a request hits the API, both worker VMs log in real time:

**Caller Worker (VM-3 — TypeScript):**
```
[caller-worker] http::add_two_numbers called {"a":42,"b":58}
[caller-worker] math::add_two_numbers called with a=42, b=58
[caller-worker] got result from math-worker: {"c":100}
```

**Math Worker (VM-4 — Python):**
```
[math-worker] math::add called with a=42, b=58
[math-worker] returning result: {'c': 100}
```

**Engine (VM-2 — registration proof):**
```
Worker registered  ip_address: Some("10.0.1.20")   ← caller-worker
Worker registered  ip_address: Some("10.0.1.30")   ← math-worker
```

Workers connect from their own private IPs — not `127.0.0.1` — proving they run on separate VMs.

---

## Resilience

Workers automatically reconnect if the engine restarts:

```
[iii] Reconnecting in 711ms (attempt 1)
[iii] Reconnecting in 1817ms (attempt 2)
[iii] Worker registered — reconnected in ~3s
```

Both workers use exponential backoff reconnection built into `iii-sdk`.
All services managed by `systemd` with `Restart=always` — workers survive crashes and reboots.

---

## Redeploy from Scratch

### Prerequisites

- AWS account with CLI configured (`aws configure`)
- Terraform >= 1.6.0
- Ansible
- SSH key at `~/.ssh/devops-intern`

### Steps

```bash
# 1. Clone the repo
git clone <your-repo-url>
cd alchemyst-devops

# 2. Generate SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/devops-intern -N ""

# 3. Provision infrastructure
cd terraform
terraform init
terraform apply -var="your_ip=$(curl -s ifconfig.me)/32"

# 4. Note the outputs
terraform output
# gateway_public_ip     = "x.x.x.x"
# engine_private_ip     = "10.0.1.10"
# caller_worker_private_ip = "10.0.1.20"
# inference_worker_private_ip = "10.0.1.30"

# 5. Configure SSH
# Edit ~/.ssh/config with the gateway public IP from step 4
# (see ssh-config-example in this repo)

# 6. Test connectivity
ssh iii-gateway "echo ok"
ssh iii-engine "echo ok"
ssh iii-caller "echo ok"
ssh iii-inference "echo ok"

# 7. Run Ansible
cd ../ansible
ansible all -i inventory/hosts.ini -m ping
ansible-playbook -i inventory/hosts.ini site.yml

# 8. Deploy workers manually (if Ansible roles need adjustment)
# See DEPLOYMENT.md for step-by-step manual deployment

# 9. Verify
curl http://<gateway-public-ip>/health
curl -X POST http://<gateway-public-ip>/math/add-two-numbers \
  -H "Content-Type: application/json" \
  -d '{"a": 10, "b": 20}'
```

### SSH Config Example

```
Host iii-gateway
  HostName <GATEWAY_PUBLIC_IP>
  User ubuntu
  IdentityFile ~/.ssh/devops-intern
  ForwardAgent yes
  StrictHostKeyChecking no

Host iii-engine
  HostName 10.0.1.10
  User ubuntu
  IdentityFile ~/.ssh/devops-intern
  ProxyJump iii-gateway
  StrictHostKeyChecking no

Host iii-caller
  HostName 10.0.1.20
  User ubuntu
  IdentityFile ~/.ssh/devops-intern
  ProxyJump iii-gateway
  StrictHostKeyChecking no

Host iii-inference
  HostName 10.0.1.30
  User ubuntu
  IdentityFile ~/.ssh/devops-intern
  ProxyJump iii-gateway
  StrictHostKeyChecking no
```

---

## Service Management

```bash
# Check all services
ssh iii-engine    "sudo systemctl status iii-engine --no-pager"
ssh iii-caller    "sudo systemctl status iii-caller-worker --no-pager"
ssh iii-inference "sudo systemctl status iii-math-worker --no-pager"
ssh iii-gateway   "sudo systemctl status nginx --no-pager"

# Watch live logs
ssh iii-inference "sudo journalctl -u iii-math-worker -f"
ssh iii-caller    "sudo journalctl -u iii-caller-worker -f"
ssh iii-engine    "sudo journalctl -u iii-engine -f"

# Restart a worker
ssh iii-inference "sudo systemctl restart iii-math-worker"
ssh iii-caller    "sudo systemctl restart iii-caller-worker"
```

---

## Network Hygiene Proof

Private VMs are NOT reachable from the internet:

```bash
curl --max-time 5 http://10.0.1.10 || echo "PASS - engine private"
curl --max-time 5 http://10.0.1.20 || echo "PASS - caller private"
curl --max-time 5 http://10.0.1.30 || echo "PASS - math private"
curl --max-time 5 http://3.108.103.134/health && echo "PASS - gateway public"
```

Only the gateway responds. All worker VMs are unreachable from the public internet.

---

## What I Would Harden for Production

1. **TLS** — Let's Encrypt cert on the gateway, HTTPS only, force HTTP→HTTPS redirect
2. **Secrets management** — AWS Secrets Manager for credentials, not environment variables
3. **IAM roles** — EC2 instance profiles instead of any static credentials
4. **VPC Flow Logs** — full network traffic audit trail for security investigations
5. **fail2ban** — SSH brute force protection on the gateway bastion
6. **WAF** — AWS WAF in front of the gateway for rate limiting and bot protection
7. **Health checks** — ALB health checks with auto-replacement of failed instances via ASG
8. **Private AMI** — bake the iii runtime and dependencies into a custom AMI so workers boot in seconds instead of minutes
9. **Monitoring** — CloudWatch alarms on CPU, memory, and service health with PagerDuty integration
10. **Immutable infrastructure** — no SSH in production, all changes go through CI/CD pipeline

---

## What Changes if the Model is 100x Larger

1. **GPU instances** — move inference worker to `g4dn.xlarge` (NVIDIA T4) or `p3.2xlarge` (V100)
2. **EFS for model weights** — shared NFS filesystem so multiple inference VMs load the same weights without re-downloading on each boot
3. **Auto Scaling Group** — inference worker behind ASG, scale out under load, scale in at night
4. **Application Load Balancer** — replace the single nginx VM with a managed ALB for high availability and health-based routing
5. **Spot instances** — run inference workers on EC2 Spot to reduce cost by ~70%, with On-Demand fallback
6. **SQS queue** — decouple gateway from workers with a request queue to absorb traffic spikes without dropping requests
7. **Model sharding** — if model doesn't fit on one GPU, use tensor parallelism across multiple GPUs with NVLink
8. **Quantization** — INT8/INT4 quantization to reduce model size and increase throughput on the same hardware
9. **Caching** — cache frequent inference results in ElastiCache Redis to avoid redundant compute
10. **Dedicated VPC endpoints** — private S3 and ECR endpoints so model weights download over AWS backbone, not the public internet

---

## Repository Structure

```
alchemyst-devops/
├── terraform/
│   ├── main.tf              # VPC, subnets, NAT gateway, route tables
│   ├── security_groups.tf   # Firewall rules per VM role
│   ├── ec2.tf               # VM definitions
│   ├── variables.tf         # Input variables
│   └── outputs.tf           # IPs and endpoints
├── ansible/
│   ├── site.yml             # Master playbook
│   ├── inventory/
│   │   └── hosts.ini        # VM inventory
│   ├── group_vars/
│   │   └── all.yml          # Shared variables
│   └── roles/
│       ├── common/          # Hardening, UFW, fail2ban
│       ├── engine/          # iii engine deployment
│       ├── gateway/         # nginx configuration
│       ├── caller-worker/   # TypeScript worker deployment
│       └── inference-worker/ # Python worker deployment
└── README.md
```
