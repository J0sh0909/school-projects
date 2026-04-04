terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# ────────────────────────────────────────────────
# AWS Provider (explicit credentials)
# ────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region
  # Credentials via environment variables:
  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# ────────────────────────────────────────────────
# No-IP & Certbot Variables
# ────────────────────────────────────────────────
variable "noip_username" {
  type    = string
  default = "group:account@noip.com"
}

variable "noip_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "noip_hostname" {
  type    = string
  default = "yourvault.ddns.net"
}

variable "certbot_email" {
  type    = string
  default = "you@example.com"
}
