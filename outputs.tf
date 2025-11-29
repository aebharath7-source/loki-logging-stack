output "instance_id" {
  description = "EC2 Instance ID"
  value       = data.aws_instance.monitoring_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = data.aws_instance.monitoring_server.public_ip
}

output "loki_url" {
  description = "Loki URL for querying logs"
  value       = "http://${data.aws_instance.monitoring_server.public_ip}:3100"
}

output "grafana_url" {
  description = "Grafana URL (existing)"
  value       = "http://${data.aws_instance.monitoring_server.public_ip}:3000"
}

output "nginx_url" {
  description = "Nginx URL (for generating logs)"
  value       = "http://${data.aws_instance.monitoring_server.public_ip}"
}

output "prometheus_url" {
  description = "Prometheus URL (existing)"
  value       = "http://${data.aws_instance.monitoring_server.public_ip}:9090"
}

output "access_instructions" {
  description = "Instructions to access the services"
  value       = <<-EOT
    
    ===================================
    🎉 Logging Stack Deployed Successfully!
    ===================================
    
    📊 Service URLs:
    ----------------
    Loki:       http://${data.aws_instance.monitoring_server.public_ip}:3100
    Grafana:    http://${data.aws_instance.monitoring_server.public_ip}:3000
    Prometheus: http://${data.aws_instance.monitoring_server.public_ip}:9090
    Nginx:      http://${data.aws_instance.monitoring_server.public_ip}
    
    🔐 Grafana Credentials:
    -----------------------
    Username: admin
    Password: admin (change on first login)
    
    📝 Next Steps:
    --------------
    1. Open Grafana: http://${data.aws_instance.monitoring_server.public_ip}:3000
    2. Add Loki data source:
       - Go to Connections → Data sources → Add data source
       - Select "Loki"
       - URL: http://localhost:3100
       - Click "Save & test"
    
    3. Explore Logs:
       - Go to Explore (compass icon)
       - Select "Loki" data source
       - Click "Log browser" and select a log stream
    
    4. Generate Nginx logs:
       - Visit: http://${data.aws_instance.monitoring_server.public_ip}
       - Refresh multiple times to generate access logs
    
    5. Query logs in Grafana:
       - Log query: {job="nginx"} or {filename="/var/log/nginx/access.log"}
    
    🔧 Verify Services:
    -------------------
    SSH to instance:
    ssh -i ${var.private_key_path} ubuntu@${data.aws_instance.monitoring_server.public_ip}
    
    Check services:
    sudo systemctl status loki
    sudo systemctl status promtail
    sudo systemctl status nginx
    
    View logs:
    sudo journalctl -u loki -f
    sudo journalctl -u promtail -f
    
    ===================================
  EOT
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.private_key_path} ubuntu@${data.aws_instance.monitoring_server.public_ip}"
}
