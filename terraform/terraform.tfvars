# ──────────────────────────────────────────────────────────────────────────────
# terraform.tfvars
# Override defaults here. Never commit secrets to git.
# ──────────────────────────────────────────────────────────────────────────────

aws_region          = "ap-south-1"
project             = "alchemyst-inference"
environment         = "dev"
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.0.0/24"
private_subnet_cidr = "10.0.1.0/24"
instance_type       = "t3.micro"
public_key_path     = "~/.ssh/devops-intern.pub"

# IMPORTANT: Replace with your actual public IP to restrict SSH access
# Find your IP: curl ifconfig.me
admin_cidr_blocks = ["0.0.0.0/0"]
