# Loki Logging Stack (Terraform)

This project deploys Loki + Promtail + Nginx on an existing EC2 instance using Terraform provisioners.

## Project layout
See the repository root for files:
- `main.tf`, `variables.tf`, `provider.tf`, `outputs.tf`
- `install-logging-stack.sh` (installation script)
- `templates/` (loki & promtail configs)
- `variables.tfvars` — update with your instance ID and key path
- `monitoring-key.pem` — place your SSH private key (do NOT commit)

## Quickstart
1. Put your private key into the repo folder (or set `private_key_path` to its path).
2. Edit `variables.tfvars`.
3. Run:
   ```bash
   terraform init
   terraform plan -var-file="variables.tfvars"
   terraform apply -var-file="variables.tfvars"
