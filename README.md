# AWS Portfolio - EC2 with SSM

This repository contains Terraform code to provision:
- An EC2 instance on the default VPC
- IAM Role + Instance Profile with AmazonSSMManagedInstanceCore
- Security Group with no inbound, all outbound
- Session Manager access (no SSH keys required)

## How to use

```bash
terraform init
terraform apply
aws ssm start-session --target <instance_id> --profile study-admin --region ap-northeast-1
