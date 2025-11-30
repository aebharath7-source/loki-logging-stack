# Data source to find existing EC2 instance by tag or instance ID
data "aws_instance" "monitoring_server" {
  instance_id = var.monitoring_instance_id

  # Alternative: filter by tag
  # filter {
  #   name   = "tag:Name"
  #   values = ["monitoring-server"]
  # }
}

# User data script for installing Loki, Promtail, and Nginx
data "template_file" "install_logging_stack" {
  template = file("${path.module}/install-logging-stack.sh")

  vars = {
    loki_version     = var.loki_version
    promtail_version = var.promtail_version
  }
}

# Create a null resource to execute the installation script
resource "null_resource" "install_logging_stack" {
  # Trigger on instance changes or script changes
  triggers = {
    instance_id = data.aws_instance.monitoring_server.id
    script_hash = md5(data.template_file.install_logging_stack.rendered)
  }

  # Connection to EC2 instance
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    host        = data.aws_instance.monitoring_server.public_ip
    timeout     = "5m"
  }

  # Copy installation script
  provisioner "file" {
    content     = data.template_file.install_logging_stack.rendered
    destination = "/tmp/install-logging-stack.sh"
  }

  # Copy Loki configuration
  provisioner "file" {
    content     = templatefile("${path.module}/templates/loki-config.yml", {})
    destination = "/tmp/loki-config.yml"
  }

  # Copy Promtail configuration
  provisioner "file" {
    content = templatefile("${path.module}/templates/promtail-config.yml", {
      loki_url = "http://localhost:3100"
    })
    destination = "/tmp/promtail-config.yml"
  }

  # Execute installation script
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-logging-stack.sh",
      "sudo /tmp/install-logging-stack.sh",
      "sleep 10"
    ]
  }
}

# Update Security Group to allow Loki port
resource "aws_security_group_rule" "allow_loki" {
  type              = "ingress"
  from_port         = 3100
  to_port           = 3100
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Loki"
  security_group_id = tolist(data.aws_instance.monitoring_server.vpc_security_group_ids)[0]
}

# Update Security Group to allow Nginx HTTP
resource "aws_security_group_rule" "allow_nginx_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Nginx HTTP"
  security_group_id = tolist(data.aws_instance.monitoring_server.vpc_security_group_ids)[0]
}

# Verify services are running
resource "null_resource" "verify_services" {
  depends_on = [null_resource.install_logging_stack]

  triggers = {
    always_run = timestamp()
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    host        = data.aws_instance.monitoring_server.public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '=== Checking Service Status ==='",
      "sudo systemctl is-active loki || echo 'Loki not running'",
      "sudo systemctl is-active promtail || echo 'Promtail not running'",
      "sudo systemctl is-active nginx || echo 'Nginx not running'",
      "echo ''",
      "echo '=== Testing Loki Endpoint ==='",
      "curl -s http://localhost:3100/ready || echo 'Loki not ready'",
      "echo ''",
      "echo '=== Testing Nginx ==='",
      "curl -s http://localhost/ > /dev/null && echo 'Nginx is working' || echo 'Nginx not responding'",
    ]
  }
}
