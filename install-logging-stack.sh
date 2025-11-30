#!/bin/bash
set -e

echo "========================================"
echo "Installing Loki Logging Stack"
echo "========================================"

LOKI_VERSION="${loki_version}"
PROMTAIL_VERSION="${promtail_version}"

###########################################
# Install Loki
###########################################
echo ""
echo "📦 Installing Loki v$LOKI_VERSION..."

cd /tmp
wget -q https://github.com/grafana/loki/releases/download/v$LOKI_VERSION/loki-linux-amd64.zip
unzip -o loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki
rm -f loki-linux-amd64.zip

# Create loki user
sudo useradd --no-create-home --shell /bin/false loki || true

# Create directories
sudo mkdir -p /etc/loki
sudo mkdir -p /var/lib/loki

# Move configuration file
sudo mv /tmp/loki-config.yml /etc/loki/loki-config.yml

# Set permissions
sudo chown -R loki:loki /etc/loki
sudo chown -R loki:loki /var/lib/loki

# Create systemd service
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

# Start Loki
sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl start loki

echo "✅ Loki installed and started"

###########################################
# Install Promtail
###########################################
echo ""
echo "📦 Installing Promtail v$PROMTAIL_VERSION..."

cd /tmp
wget -q https://github.com/grafana/loki/releases/download/v$PROMTAIL_VERSION/promtail-linux-amd64.zip
unzip -o promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail
rm -f promtail-linux-amd64.zip

# Create promtail user
sudo useradd --no-create-home --shell /bin/false promtail || true

# Create directories
sudo mkdir -p /etc/promtail

# Move configuration file
sudo mv /tmp/promtail-config.yml /etc/promtail/promtail-config.yml

# Set permissions
sudo chown -R promtail:promtail /etc/promtail

# Add promtail user to adm group to read logs
sudo usermod -aG adm promtail || true

# Create systemd service
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

# Start Promtail
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail

echo "✅ Promtail installed and started"

###########################################
# Install and Configure Nginx
###########################################
echo ""
echo "📦 Installing Nginx..."

sudo apt-get update -qq
sudo apt-get install -y nginx

# Create a custom index page
sudo tee /var/www/html/index.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Logging Stack Demo</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        .status {
            padding: 10px;
            margin: 10px 0;
            background: #e8f5e9;
            border-left: 4px solid #4caf50;
        }
        button {
            background: #2196F3;
            color: white;
            border: none;
            padding: 10px 20px;
            margin: 5px;
            cursor: pointer;
            border-radius: 5px;
        }
        button:hover { background: #0b7dda; }
        .log-entry {
            background: #f5f5f5;
            padding: 10px;
            margin: 5px 0;
            font-family: monospace;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 Logging Stack Demo</h1>

        <div class="status">
            <strong>✅ Nginx is running!</strong><br>
            Every page load creates a log entry that Promtail sends to Loki.
        </div>

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

        <h2>Quick Start:</h2>
        <ol>
            <li>Open Grafana and add Loki data source: <code>http://localhost:3100</code></li>
            <li>Go to Explore → Select Loki</li>
            <li>Query: <code>{job="nginx"}</code> or <code>{filename="/var/log/nginx/access.log"}</code></li>
            <li>Click buttons above to generate logs and see them in Grafana!</li>
        </ol>

        <div id="logs"></div>
    </div>

    <script>
        function generateLog(type) {
            const logsDiv = document.getElementById('logs');
            const timestamp = new Date().toISOString();

            if (type === 'multiple') {
                for (let i = 0; i < 10; i++) {
                    fetch('/api/log?type=batch&id=' + i);
                }
                logsDiv.innerHTML = '<div class="log-entry">' + timestamp + ' - Generated 10 log entries</div>' + logsDiv.innerHTML;
            } else {
                fetch('/api/log?type=' + type);
                logsDiv.innerHTML = '<div class="log-entry">' + timestamp + ' - Generated ' + type.toUpperCase() + ' log</div>' + logsDiv.innerHTML;
            }
        }

        // Auto-refresh every 5 seconds to generate logs
        setInterval(() => {
            fetch('/healthcheck');
        }, 5000);
    </script>
</body>
</html>
EOF

# Start and enable Nginx
sudo systemctl enable nginx
sudo systemctl restart nginx

echo "✅ Nginx installed and configured"

###########################################
# Verify Installation
###########################################
echo ""
echo "========================================"
echo "🔍 Verifying Installation..."
echo "========================================"

sleep 5

# Check Loki
if sudo systemctl is-active --quiet loki; then
    echo "✅ Loki is running"
else
    echo "❌ Loki is not running"
fi

# Check Promtail
if sudo systemctl is-active --quiet promtail; then
    echo "✅ Promtail is running"
else
    echo "❌ Promtail is not running"
fi

# Check Nginx
if sudo systemctl is-active --quiet nginx; then
    echo "✅ Nginx is running"
else
    echo "❌ Nginx is not running"
fi

# Test Loki endpoint
if curl -s http://localhost:3100/ready > /dev/null; then
    echo "✅ Loki is responding on port 3100"
else
    echo "❌ Loki is not responding"
fi

# Test Nginx
if curl -s http://localhost/ > /dev/null; then
    echo "✅ Nginx is responding on port 80"
else
    echo "❌ Nginx is not responding"
fi

echo ""
echo "========================================"
echo "✅ Installation Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Add Loki data source in Grafana: http://localhost:3100"
echo "2. Explore logs in Grafana using query: {job=\"nginx\"}"
echo "3. Generate logs by visiting Nginx: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo ""
