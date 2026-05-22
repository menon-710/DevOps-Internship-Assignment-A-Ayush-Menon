###############################################################################
# Alchemyst AI – Distributed Inference Stack
# Author : Ayush (DevOps Intern Submission)
# Region : ap-south-1 (Mumbai)
#
# Topology
#   VPC 10.0.0.0/16
#   ├── public  subnet 10.0.0.0/24  → nginx gateway  (t2.micro)
#   └── private subnet 10.0.1.0/24  → iii engine     (t2.micro)
#                                    → caller-worker  (t2.micro)
#                                    → inference-worker (t2.micro)
#
# Traffic rules
#   • Only the gateway has a public IP / internet-facing port 80 & 443
#   • Private VMs reach the internet through a NAT Gateway (for apt/pip/model)
#   • Workers communicate with the engine only on port 49134 (WebSocket)
#   • nginx proxies /v1/* → engine REST port 3111
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to use S3 backend for team collaboration
  # backend "s3" {
  #   bucket = "alchemyst-tfstate"
  #   key    = "inference-stack/terraform.tfstate"
  #   region = "ap-south-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "alchemyst-inference"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "devops-intern"
    }
  }
}

###############################################################################
# DATA SOURCES
###############################################################################

# Latest Ubuntu 22.04 LTS AMI – always fresh, no hardcoded AMI IDs
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Current AWS account ID (used in IAM policies)
data "aws_caller_identity" "current" {}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project}-vpc" }
}

###############################################################################
# SUBNETS
###############################################################################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = { Name = "${var.project}-private-subnet" }
}

###############################################################################
# INTERNET GATEWAY  (public subnet → internet)
###############################################################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

###############################################################################
# NAT GATEWAY  (private subnet → internet, one-way)
###############################################################################

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "${var.project}-nat-gw" }
}

###############################################################################
# ROUTE TABLES
###############################################################################

# Public route table – default route to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table – default route to NAT GW
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "${var.project}-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

###############################################################################
# SECURITY GROUPS
###############################################################################

# ── Gateway SG ──────────────────────────────────────────────────────────────
# Accepts HTTP/HTTPS from world; SSH only from your IP
resource "aws_security_group" "gateway" {
  name        = "${var.project}-gateway-sg"
  description = "nginx API gateway - public facing"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-gateway-sg" }
}

# ── Engine SG ────────────────────────────────────────────────────────────────
# Accepts WebSocket (49134) and REST (3111) only from private subnet
resource "aws_security_group" "engine" {
  name        = "${var.project}-engine-sg"
  description = "iii engine - private only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "WebSocket from private subnet (workers)"
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "REST API from gateway"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  ingress {
    description = "REST API from private subnet"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "SSH from gateway (bastion hop)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-engine-sg" }
}

# ── Worker SG ────────────────────────────────────────────────────────────────
# Workers only need to reach out (to engine). No inbound except SSH from gateway.
resource "aws_security_group" "worker" {
  name        = "${var.project}-worker-sg"
  description = "inference and caller workers - private only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from gateway (bastion hop)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    description = "All outbound (to engine WebSocket + internet for deps)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-worker-sg" }
}

###############################################################################
# SSH KEY PAIR
###############################################################################

resource "aws_key_pair" "deployer" {
  key_name   = "${var.project}-key"
  public_key = file(var.public_key_path)
  tags       = { Name = "${var.project}-keypair" }
}

###############################################################################
# EC2 INSTANCES
###############################################################################

# ── VM-1: API Gateway (nginx) ────────────────────────────────────────────────
resource "aws_instance" "gateway" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gateway.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname gateway
    apt-get update -y
    apt-get install -y nginx curl
    systemctl enable nginx
  EOF

  tags = { Name = "${var.project}-gateway", Role = "gateway" }
}

# ── VM-2: iii Engine ─────────────────────────────────────────────────────────
resource "aws_instance" "engine" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.engine.id]
  key_name               = aws_key_pair.deployer.key_name
  private_ip             = "10.0.1.10"

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname iii-engine
    apt-get update -y
    apt-get install -y curl
  EOF

  tags = { Name = "${var.project}-engine", Role = "engine" }
}

# ── VM-3: Caller Worker (TypeScript) ─────────────────────────────────────────
resource "aws_instance" "caller_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.worker.id]
  key_name               = aws_key_pair.deployer.key_name
  private_ip             = "10.0.1.20"

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname caller-worker
    apt-get update -y
    apt-get install -y curl
  EOF

  tags = { Name = "${var.project}-caller-worker", Role = "caller-worker" }
}

# ── VM-4: Inference Worker (Python + Gemma) ───────────────────────────────────
resource "aws_instance" "inference_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.worker.id]
  key_name               = aws_key_pair.deployer.key_name
  private_ip             = "10.0.1.30"

  # Inference worker needs more disk – model is ~270MB but deps add up
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname inference-worker
    apt-get update -y
    apt-get install -y curl python3 python3-pip python3-venv
  EOF

  tags = { Name = "${var.project}-inference-worker", Role = "inference-worker" }
}

###############################################################################
# ELASTIC IP for Gateway (stable public IP across stop/start)
###############################################################################

resource "aws_eip" "gateway" {
  instance   = aws_instance.gateway.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project}-gateway-eip" }
}
