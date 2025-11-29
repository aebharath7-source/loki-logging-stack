variable "aws_region" {
  description = "AWS region where the EC2 instance is located"
  type        = string
  default     = "us-east-1"
}

variable "monitoring_instance_id" {
  description = "Instance ID of the existing monitoring EC2 instance"
  type        = string
}

variable "private_key_path" {
  description = "Path to the SSH private key file for EC2 access"
  type        = string
}

variable "loki_version" {
  description = "Version of Loki to install"
  type        = string
  default     = "2.9.3"
}

variable "promtail_version" {
  description = "Version of Promtail to install"
  type        = string
  default     = "2.9.3"
}
