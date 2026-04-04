##########################################
# TLS key → AWS key pair → local PEM file
##########################################

resource "tls_private_key" "vaultwarden" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vaultwarden" {
  key_name   = "vaultwarden-key"
  public_key = tls_private_key.vaultwarden.public_key_openssh
}

resource "local_file" "vaultwarden_pem" {
  content         = tls_private_key.vaultwarden.private_key_pem
  filename        = "${path.module}/vaultwarden-key.pem"
  file_permission = "0600"
}

##########################################
# Networking
##########################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "vaultwarden-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "vaultwarden-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = false   # instance private until EIP attached
  tags = { Name = "vaultwarden-subnet" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "vaultwarden-rt" }
}

resource "aws_route_table_association" "assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

##########################################
# Security group
##########################################

resource "aws_security_group" "web_sg" {
  name        = "vaultwarden-sg"
  description = "Allow SSH, HTTP, HTTPS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vaultwarden-sg" }
}

##########################################
# Elastic IP
##########################################

resource "aws_eip" "vault" {
  domain = "vpc"
  tags   = { Name = "vaultwarden-eip" }
}

##########################################
# Ubuntu 24.04 AMI
##########################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

##########################################
# EC2 Instance (created first)
##########################################

resource "aws_instance" "vault" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.vaultwarden.key_name

  tags = { Name = "vaultwarden-instance" }
}

##########################################
# Elastic IP Association (attach after instance)
##########################################

resource "aws_eip_association" "assoc" {
  allocation_id        = aws_eip.vault.id
  network_interface_id = aws_instance.vault.primary_network_interface_id
}

##########################################
# Provisioning (runs after EIP attached)
##########################################

resource "null_resource" "provision_vault" {
  depends_on = [aws_eip_association.assoc]

  provisioner "file" {
    source      = "${path.module}/script.sh"
    destination = "/home/ubuntu/script.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_eip.vault.public_ip
      private_key = tls_private_key.vaultwarden.private_key_pem
      timeout     = "10m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/script.sh",
      "sudo DOMAIN='${var.noip_hostname}' EMAIL='${var.certbot_email}' EIP='${aws_eip.vault.public_ip}' /home/ubuntu/script.sh"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = aws_eip.vault.public_ip
      private_key = tls_private_key.vaultwarden.private_key_pem
      timeout     = "10m"
    }
  }
}

##########################################
# Outputs
##########################################

output "elastic_ip" {
  value = aws_eip.vault.public_ip
}

output "vaultwarden_url" {
  value = "https://${var.noip_hostname}"
}
