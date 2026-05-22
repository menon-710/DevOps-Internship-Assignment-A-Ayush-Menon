###############################################################################
# Variables
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name prefix – used for all resource names and tags"
  type        = string
  default     = "alchemyst-inference"
}

variable "environment" {
  description = "Environment label (dev / staging / prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (gateway lives here)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet (all workers live here)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for all VMs"
  type        = string
  default     = "t3.micro" # Free tier eligible
}

variable "public_key_path" {
  description = "Path to the SSH public key to provision on all VMs"
  type        = string
  default     = "~/.ssh/devops-intern.pub"
}

variable "admin_cidr_blocks" {
  description = "Your IP(s) allowed to SSH into the gateway. Set to your own IP for security."
  type        = list(string)
  default     = ["0.0.0.0/0"] # NARROW THIS DOWN in production!
}
