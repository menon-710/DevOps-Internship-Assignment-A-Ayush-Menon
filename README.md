# Alchemyst AI – Distributed iii RPC Stack

> DevOps Internship Submission · May 2026  
> Distributed RPC-based AI inference infrastructure deployed on AWS using Terraform, Ansible, nginx, Flask, and the iii framework.

---

# Overview

This project deploys the `iii quickstart` distributed worker architecture across multiple AWS virtual machines inside a secure private subnet.

The infrastructure exposes a public HTTP API through an nginx gateway, while all internal RPC communication happens securely over WebSockets inside the private network.

The stack demonstrates:

- Infrastructure as Code using Terraform
- Automated provisioning with Ansible
- Multi-VM distributed architecture
- RPC-based worker communication
- Secure subnet isolation
- HTTP API exposure through reverse proxying
- Horizontal worker scaling capability

---

# Architecture

```text
                  AWS ap-south-1
                VPC: 10.0.0.0/16
────────────────────────────────────────

                Internet Gateway
                        │
        ┌────────────────────────────────┐
        │ Public Subnet 10.0.0.0/24     │
        │                                │
        │  VM-1: nginx Gateway           │
        │  Public IP: 3.108.103.134      │
        │  Ports: 80, 443                │
        └──────────────┬─────────────────┘
                       │
                 proxy_pass :5000
                       │
        ┌────────────────────────────────┐
        │ Private Subnet 10.0.1.0/24    │
        │                                │
        │ VM-2: iii Engine               │
        │ 10.0.1.10                      │
        │                                │
        │ - Flask API wrapper            │
        │ - math-worker                  │
        │ - caller-worker                │
        │                                │
        │ Port 5000 (internal API)       │
        │ Port 49134 (WebSocket RPC)     │
        └────────────────────────────────┘
```

---

# API Reference

## POST `/v1/trigger`

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

### Response

```json
{
  "args": {
    "a": 5,
    "b": 7
  },
  "function": "add",
  "result": "{\n  \"c\": 12\n}",
  "worker": "math"
}
```

---

# Deployment

## Terraform

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Ansible

```bash
cd ansible
ansible-playbook -i inventory.ini site.yml -v
```

---

# Repository Structure

```text
alchemyst-devops/
├── terraform/
├── ansible/
├── api-gateway/
├── scripts/
└── README.md
```

---

# Production Hardening

- TLS with ACM certificates
- IAM least privilege
- AWS Secrets Manager
- CloudWatch + OpenTelemetry
- SSM Session Manager
- systemd worker services
- KVM-based worker isolation

---

# Technology Stack

- AWS EC2
- Terraform
- Ansible
- nginx
- Flask
- Ubuntu 22.04
- iii Framework
- WebSocket RPC
- systemd

---

# Author

**A Ayush Menon**  
Alchemyst AI DevOps Internship · May 2026
