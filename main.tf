terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "study-admin"
}

# ---------------------------
# デフォルトVPC・サブネットを取得
# ---------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_for_az" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  default_subnet_id = data.aws_subnets.default_for_az.ids[0]

  common_tags = {
    Project = "aws-portfolio-ecsite"
    Owner   = "takuya"
    Env     = "dev"
  }
}

# ---------------------------
# IAMロール（SSM用）
# ---------------------------
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-ssm-role-tf"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Effect : "Allow",
      Principal : { Service : "ec2.amazonaws.com" },
      Action : "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2-ssm-instance-profile-tf"
  role = aws_iam_role.ec2_ssm_role.name
  tags = local.common_tags
}

# ---------------------------
# セキュリティグループ（インバウンドなし／アウトバウンドALL）
# ---------------------------
resource "aws_security_group" "ec2_min" {
  name        = "ec2-ssm-only"
  description = "No ingress; egress all. Use SSM for access."
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = local.common_tags
}

# ---------------------------
# EC2インスタンス（Amazon Linux 2023）
# ---------------------------
data "aws_ami" "al2023" {
  owners      = ["137112412989"] # Amazon公式
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = local.default_subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2_min.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_profile.name
  associate_public_ip_address = true
  key_name                    = null # SSHキーは使わない

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
  EOT

  tags = merge(local.common_tags, { Name = "ec2-ssm-demo" })
}

# ---------------------------
# 出力
# ---------------------------
output "instance_id" {
  value = aws_instance.web.id
}

output "public_ip" {
  value = aws_instance.web.public_ip
}

output "ssm_command" {
  value = "aws ssm start-session --target ${aws_instance.web.id} --profile study-admin --region ap-northeast-1"
}
