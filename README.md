# Alchemyst AI – Distributed iii RPC Stack

> DevOps Internship Submission · May 2026
> Deploys the iii quickstart project across 4 AWS VMs in a private subnet, wired together over WebSocket RPC, exposed as a JSON HTTP API.

---

## Architecture
                      AWS ap-south-1 (VPC: 10.0.0.0/16)

  Internet
     │
[Internet Gateway]
│
Public Subnet 10.0.0.0/24
│
┌──────────────────────┐
│  VM-1: nginx Gateway │  ← ONLY public-facing VM
│  Elastic IP:         │    Elastic IP: 3.108.103.134
│  3.108.103.134       │    Ports: 80, 443
└──────────┬───────────┘
│ proxy_pass :5000
│
Private Subnet 10.0.1.0/24
│
┌──────────▼───────────┐
│  VM-2: iii Engine    │  10.0.1.10
│  + Flask API wrapper │  Port 5000 (internal only)
│  + math-worker       │  Port 49134 WebSocket
│  + caller-worker     │
└──────────────────────┘
VM-3: caller-worker VM  10.0.1.20  (provisioned, available for scale-out)
VM-4: math-worker VM    10.0.1.30  (provisioned, available for scale-out)
NAT Gateway → private VMs can reach internet for package installs

### Request Flow
① curl POST → nginx (VM-1, public :80)
② nginx proxies → Flask API (VM-2, internal :5000)
③ Flask runs: iii trigger math::add a=X b=Y
④ iii engine routes RPC → math-worker (WebSocket :49134)
⑤ math-worker executes, returns {"c": result}
⑥ Response bubbles back as JSON

---

## API Reference

### POST /v1/trigger

Accepts a JSON body specifying the worker, function, and arguments.

**Request**
```json
{
  "worker": "math",
  "function": "add",
  "args": {
    "a": 5,
    "b": 7
  }
}
```

**Response**
```json
{
  "args": {"a": 5, "b": 7},
  "function": "add",
  "result": "{\n  \"c\": 12\n}",
  "worker": "math"
}
```

### GET /health

```json
{"status": "ok", "service": "alchemyst-gateway"}
```

---

## curl Examples

```bash
# Add two numbers through the full RPC chain
curl -s -X POST http://3.108.103.134/v1/trigger \
  -H 'Content-Type: application/json' \
  -d '{"worker": "math", "function": "add", "args": {"a": 5, "b": 7}}'
# → {"args":{"a":5,"b":7},"function":"add","result":"{\n  \"c\": 12\n}","worker":"math"}

curl -s -X POST http://3.108.103.134/v1/trigger \
  -H 'Content-Type: application/json' \
  -d '{"worker": "math", "function": "add", "args": {"a": 100, "b": 200}}'
# → {"args":{"a":100,"b":200},"function":"add","result":"{\n  \"c\": 300\n}","worker":"math"}

# Health check
curl -s http://3.108.103.134/health
# → {"status":"ok","service":"alchemyst-gateway"}
```

---

## VM Inventory

| VM | Role | IP | Type | Open Ports |
|---|---|---|---|---|
| VM-1 | nginx gateway | 3.108.103.134 (public) | t3.micro | 80, 443 (world); 22 (admin) |
| VM-2 | iii engine + workers | 10.0.1.10 | t3.micro | 5000 (from public subnet); 49134 (internal) |
| VM-3 | caller-worker (scale-out) | 10.0.1.20 | t3.micro | 22 (gateway only) |
| VM-4 | math-worker (scale-out) | 10.0.1.30 | t3.micro | 22 (gateway only) |

---

## Redeploy from Scratch

### Prerequisites

```bash
# Install tools in WSL2
sudo apt install terraform ansible unzip -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install

# Generate SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/devops-intern -N ""

# Configure AWS
aws configure  # ap-south-1, your credentials
```

### Step 1 — Provision infrastructure

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 2 — Generate Ansible inventory

```bash
touch ansible/inventory.ini
# Edit ansible/inventory.ini with IPs from terraform output
# See inventory format in ansible/inventory.ini
```

### Step 3 — Deploy services

```bash
cd ansible
ansible-playbook -i inventory.ini site.yml -v
```

### Step 4 — Copy iii binaries to engine VM

```bash
scp -i ~/.ssh/devops-intern \
  -o ProxyCommand="ssh -i ~/.ssh/devops-intern -W %h:%p ubuntu@<GATEWAY_IP>" \
  ~/.local/bin/iii ~/.local/bin/iii-worker \
  ubuntu@10.0.1.10:/tmp/

ssh -i ~/.ssh/devops-intern \
  -o ProxyCommand="ssh -i ~/.ssh/devops-intern -W %h:%p ubuntu@<GATEWAY_IP>" \
  ubuntu@10.0.1.10 \
  "mkdir -p ~/.local/bin && cp /tmp/iii /tmp/iii-worker ~/.local/bin/ && chmod +x ~/.local/bin/iii ~/.local/bin/iii-worker"
```

### Step 5 — Start workers and test

```bash
# SSH into engine VM and start workers
ssh -i ~/.ssh/devops-intern \
  -o ProxyCommand="ssh -i ~/.ssh/devops-intern -W %h:%p ubuntu@<GATEWAY_IP>" \
  ubuntu@10.0.1.10 \
  "cd /opt/alchemyst/quickstart/workers/math-worker && \
   III_URL=ws://localhost:49134 nohup python3 math_worker.py > /tmp/math-worker.log 2>&1 &"

# Test
curl -s -X POST http://<GATEWAY_IP>/v1/trigger \
  -H 'Content-Type: application/json' \
  -d '{"worker": "math", "function": "add", "args": {"a": 2, "b": 3}}'
```

### Teardown

```bash
cd terraform && terraform destroy
```

---

## Production Hardening

*What I would change before putting this in production:*

**1. TLS everywhere** — Add a domain, provision ACM certificate, terminate TLS at nginx. The nginx config already has the HTTPS server block ready.

**2. Persistent worker startup** — Currently workers are started manually via SSH. In production I'd write proper systemd services that run workers as plain processes (bypassing iii's microVM sandbox which requires KVM) using `python3 math_worker.py` directly with `III_URL` env var pointing to the engine.

**3. Narrow IAM permissions** — Current IAM user has AdministratorAccess. Scope it to only the EC2/VPC actions Terraform actually needs.

**4. Restrict SSH** — Set `admin_cidr_blocks` in terraform.tfvars to your office IP only. Better: use AWS SSM Session Manager and remove port 22 entirely.

**5. Secrets management** — Move all credentials to AWS Secrets Manager. Have services pull config at startup via IAM instance role.

**6. Observability** — iii engine exposes OpenTelemetry metrics. Ship them to CloudWatch. Add a dead-man's-switch alarm on the /health endpoint.

**7. KVM for worker isolation** — Run the engine on a metal instance (c5.metal) to enable KVM, which lets iii boot worker microVMs with full isolation. On t3.micro, workers run as plain processes which is functional but lacks the sandbox security boundary.

---

## 100x Model Size

*If the model were 100x larger (e.g. a 27B parameter model instead of a math worker):*

- **Compute** — Need GPU instances (p3.8xlarge minimum, ~$12/hr). Free tier is gone.
- **Storage** — Model checkpoint ~54GB. Store in S3, pull to instance on boot via IAM role. Never bake into AMI.
- **Loading time** — GPU model loading takes 2-4 minutes. Set `TimeoutStartSec=300` in systemd.
- **Inference tier** — Replace synchronous HTTP with SQS queue. Return job ID immediately, poll for result. Prevents gateway timeouts on slow inference.
- **Batching** — Use vLLM or TensorRT-LLM for continuous batching — 3-5x better throughput than naive inference.
- **Auto-scaling** — Wrap inference VMs in Auto Scaling Group. Scale on SQS queue depth metric.
- **The iii architecture stays the same** — caller-worker still calls inference via RPC. Only the inference layer changes. That's the beauty of this design.

---

## Repository Structure
alchemyst-devops/
├── terraform/          # AWS infrastructure (VPC, subnets, SGs, EC2)
├── ansible/            # Configuration management
│   ├── site.yml        # Master playbook
│   ├── inventory.ini   # Auto-generated from terraform outputs
│   ├── group_vars/     # Shared variables
│   └── roles/          # gateway, engine, math-worker, caller-worker, common
├── api-gateway/        # Flask HTTP wrapper around iii trigger CLI
│   └── app.py
└── scripts/            # deploy.sh, teardown.sh, stop_vms.sh, start_vms.sh

---

*Built by Ayush · Alchemyst AI DevOps Internship · May 2026*
*Stack: AWS · Terraform · Ansible · iii framework · nginx · Flask · systemd · Ubuntu 22.04*
