# main.tf - robust: uploads raw script, creates SG rules for every attached SG id

data "aws_instance" "monitoring_server" {
  instance_id = var.monitoring_instance_id
}

# read the install script as raw file (no template interpolation)
locals {
  install_script = file("${path.module}/install-logging-stack.sh")
}

resource "null_resource" "install_logging_stack" {
  # Trigger when the instance or the script content changes
  triggers = {
    instance_id = data.aws_instance.monitoring_server.id
    script_hash = md5(local.install_script)
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    host        = data.aws_instance.monitoring_server.public_ip
    timeout     = "5m"
  }

  # Upload raw script (no Terraform interpolation)
  provisioner "file" {
    content     = local.install_script
    destination = "/tmp/install-logging-stack.sh"
  }

  # Upload Loki config (use templatefile for configs that intentionally use TF variables)
  provisioner "file" {
    content     = templatefile("${path.module}/templates/loki-config.yml", {})
    destination = "/tmp/loki-config.yml"
  }

  # Upload Promtail config (we inject loki_url)
  provisioner "file" {
    content = templatefile("${path.module}/templates/promtail-config.yml", {
      loki_url = "http://localhost:3100"
    })
    destination = "/tmp/promtail-config.yml"
  }

  # Execute installation script and pass versions as env vars (prevent Terraform from touching script contents)
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-logging-stack.sh",
      "sudo LOKI_VERSION='${var.loki_version}' PROMTAIL_VERSION='${var.promtail_version}' /tmp/install-logging-stack.sh || (sudo journalctl -u loki -n 50; sudo journalctl -u promtail -n 50; exit 1)"
    ]
  }
}

# --- Recommended: create one SG rule per attached security group using for_each ---
# Create ingress rule for Loki (port 3100) across every SG attached to the instance
resource "aws_security_group_rule" "allow_loki" {
  for_each = toset(data.aws_instance.monitoring_server.vpc_security_group_ids)

  type              = "ingress"
  from_port         = 3100
  to_port           = 3100
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Loki"
  security_group_id = each.value
}

# Create ingress rule for Nginx (port 80) across every SG attached to the instance
resource "aws_security_group_rule" "allow_nginx_http" {
  for_each = toset(data.aws_instance.monitoring_server.vpc_security_group_ids)

  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Nginx HTTP"
  security_group_id = each.value
}

# Verify services are running after install
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
      "curl -s http://localhost/ > /dev/null && echo 'Nginx is working' || echo 'Nginx not responding'"
    ]
  }
}
