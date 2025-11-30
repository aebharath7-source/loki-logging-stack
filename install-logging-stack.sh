#!/bin/bash
set -e

echo "========================================"
echo "Installing Loki Logging Stack"
echo "========================================"

# Versions passed via environment variables by Terraform remote-exec:
# LOKI_VERSION and PROMTAIL_VERSION
LOKI_VERSION="${LOKI_VERSION:-${loki_version:-2.9.3}}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-${promtail_version:-2.9.3}}"

# Function to check status of last command
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ $1 FAILED"
        exit 1
    fi
}

###########################################
# Ensure basic tools are installed first
###########################################
echo ""
echo "🔧 Ensuring required packages (wget, unzip, curl, ca-certificates) are installed..."

# Detect apt-get (Debian/Ubuntu). Add support for yum later if needed.
if command -v apt-get >/dev/null 2>&1; then
    # Update and install quietly
    sudo apt-get update -qq
    sudo apt-get install -y -qq wget unzip curl ca-certificates gnupg lsb-release
    check_status "Installed apt packages"
else
    echo "⚠️  apt-get not found. Please ensure wget, unzip and curl are installed on the instance."
fi

###########################################
# Working dir
###########################################
cd /tmp

###########################################
# Install Loki
###########################################
echo ""
echo "📦 Installing Loki v${LOKI_VERSION}..."

# Download Loki
echo "Downloading Loki..."
wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"
check_status "Loki download"

# Extract and move binary
echo "Installing Loki binary..."
unzip -o loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki
rm -f loki-linux-amd64.zip
check_status "Loki binary installation"

# Verify Loki binary (non-fatal)
if /usr/local/bin/loki --version >/dev/null 2>&1; then
    echo "✅ Loki binary verification succeeded"
else
    echo "⚠️ Loki version check failed; binary may still be present"
fi

# Create loki user (ignore if exists)
sudo useradd --no-create-home --shell /bin/false loki 2>/dev/null || true

# Create directories
sudo mkdir -p /etc/loki
sudo mkdir -p /var/lib/loki
sudo mkdir -p /var/lib/loki/chunks
sudo mkdir -p /var/lib/loki/rules

# Move or create loki config
if [ -f /tmp/loki-config.yml ]; then
    echo "Using uploaded /tmp/loki-config.yml"
    sudo mv /tmp/loki-config.yml /etc/loki/loki-config.yml
else
    echo "No /tmp/loki-config.yml found — creating default /etc/loki/loki-config.yml"
    sudo tee /etc/loki/loki-config.yml > /dev/null <<'LOKIEOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093
LOKIEOF
fi
check_status "Loki configuration"

# Set permissions for Loki
sudo chown -R loki:loki /etc/loki
sudo chown -R loki:loki /var/lib/loki

# Create systemd service for Loki
sudo tee /etc/systemd/system/loki.service > /dev/null <<'EOF'
[Unit]
Description=Loki Log Aggregation System
After=network.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
check_status "Loki service file creation"

# Start Loki
sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl restart loki || true
sleep 3

if sudo systemctl is-active --quiet loki; then
    echo "✅ Loki is running"
else
    echo "❌ Loki failed to start. Dumping last 40 lines of journal..."
    sudo journalctl -u loki -n 40 --no-pager || true
fi

###########################################
# Install Promtail
###########################################
echo ""
echo "📦 Installing Promtail v${PROMTAIL_VERSION}..."

# Download Promtail
echo "Downloading Promtail..."
wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
check_status "Promtail download"

# Extract and move binary
echo "Installing Promtail binary..."
unzip -o promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail
rm -f promtail-linux-amd64.zip
check_status "Promtail binary installation"

# Verify Promtail (non-fatal)
if /usr/local/bin/promtail --version >/dev/null 2>&1; then
    echo "✅ Promtail binary verification succeeded"
else
    echo "⚠️ Promtail version check failed; binary may still be present"
fi

# Create promtail user
sudo useradd --no-create-home --shell /bin/false promtail 2>/dev/null || true

# Create directories
sudo mkdir -p /etc/promtail

# Move or create promtail config
if [ -f /tmp/promtail-config.yml ]; then
    echo "Using uploaded /tmp/promtail-config.yml"
    sudo mv /tmp/promtail-config.yml /etc/promtail/promtail-config.yml
else
    echo "No /tmp/promtail-config.yml found — creating default /etc/promtail/promtail-config.yml"
    sudo tee /etc/promtail/promtail-config.yml > /dev/null <<'PROMEOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          __path__: /var/log/nginx/access.log

  - job_name: nginx-error
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx-error
          __path__: /var/log/nginx/error.log

  - job_name: varlogs
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*.log

  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
PROMEOF
fi
check_status "Promtail configuration"

# Permissions
sudo chown -R promtail:promtail /etc/promtail

# Add promtail to adm group to allow reading /var/log
sudo usermod -aG adm promtail || true

# Create systemd service for promtail
sudo tee /etc/systemd/system/promtail.service > /dev/null <<'EOF'
[Unit]
Description=Promtail Log Collector
After=network.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
check_status "Promtail service file creation"

# Start Promtail
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl restart promtail || true
sleep 3

if sudo systemctl is-active --quiet promtail; then
    echo "✅ Promtail is running"
else
    echo "❌ Promtail failed to start. Dumping last 40 lines of journal..."
    sudo journalctl -u promtail -n 40 --no-pager || true
fi

###########################################
# Install and configure Nginx (demo page)
###########################################
echo ""
echo "📦 Installing Nginx..."

sudo apt-get update -qq
sudo apt-get install -y -qq nginx
check_status "Nginx installation"

# Create demo index page
sudo tee /var/www/html/index.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Logging Stack Demo</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .status { padding: 10px; margin: 10px 0; background: #e8f5e9; border-left: 4px solid #4caf50; }
        button { background: #2196F3; color: white; border: none; padding: 10px 20px; margin: 5px; cursor: pointer; border-radius: 5px; }
        .log-entry { background: #f5f5f5; padding: 10px; margin: 5px 0; font-family: monospace; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 Logging Stack Demo</h1>
        <div class="status"><strong>✅ Nginx is running!</strong><br>Every page load creates a log entry that Promtail sends to Loki.</div>
        <h2>Generate Logs:</h2>
        <button onclick="generateLog('info')">Generate INFO Log</button>
        <button onclick="generateLog('error')">Generate ERROR Log</button>
        <button onclick="generateLog('multiple')">Generate 10 Logs</button>
        <h2>Service URLs:</h2>
        <ul>
            <li><a href="http://localhost:3000" target="_blank">Grafana (Port 3000)</a></li>
            <li><a href="http://localhost:9090" target="_blank">Prometheus (Port 9090)</a></li>
            <li><a href="http://localhost:3100/ready" target="_blank">Loki (Port 3100)</a></li>
        </ul>
        <div id="logs"></div>
    </div>
    <script>
        function generateLog(type) {
            const logsDiv = document.getElementById('logs');
            const timestamp = new Date().toISOString();
            if (type === 'multiple') {
                for (let i = 0; i < 10; i++) { fetch('/api/log?type=batch&id=' + i); }
                logsDiv.innerHTML = '<div class="log-entry">' + timestamp + ' - Generated 10 log entries</div>' + logsDiv.innerHTML;
            } else {
                fetch('/api/log?type=' + type);
                logsDiv.innerHTML = '<div class="log-entry">' + timestamp + ' - Generated ' + type.toUpperCase() + ' log</div>' + logsDiv.innerHTML;
            }
        }
        setInterval(() => { fetch('/healthcheck'); }, 5000);
    </script>
</body>
</html>
EOF

sudo systemctl enable nginx
sudo systemctl restart nginx || true
check_status "Nginx service start"

###########################################
# Final verification
###########################################
echo ""
echo "========================================"
echo "🔍 Verifying Installation..."
echo "========================================"
sleep 4

ERRORS=0

if sudo systemctl is-active --quiet loki; then
    echo "✅ Loki is running"
else
    echo "❌ Loki is not running"
    ERRORS=$((ERRORS + 1))
fi

if sudo systemctl is-active --quiet promtail; then
    echo "✅ Promtail is running"
else
    echo "❌ Promtail is not running"
    ERRORS=$((ERRORS + 1))
fi

if sudo systemctl is-active --quiet nginx; then
    echo "✅ Nginx is running"
else
    echo "❌ Nginx is not running"
    ERRORS=$((ERRORS + 1))
fi

if curl -s http://localhost:3100/ready >/dev/null 2>&1; then
    echo "✅ Loki HTTP ready"
else
    echo "❌ Loki HTTP not ready"
    ERRORS=$((ERRORS + 1))
fi

if curl -s http://localhost/ >/dev/null 2>&1; then
    echo "✅ Nginx responding"
else
    echo "❌ Nginx not responding"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ Installation Complete - All Services Running!"
else
    echo "⚠️ Installation completed with $ERRORS error(s). Check journalctl for details."
    echo "Example: sudo journalctl -u loki -n 50"
fi

echo ""
echo "Next steps:"
echo "1) Add Loki data source in Grafana: http://localhost:3100"
echo "2) View logs in Grafana Explore using {job=\"nginx\"}"
echo "3) If problems persist, SSH to the instance and inspect: sudo journalctl -u loki -n 200"
echo ""


