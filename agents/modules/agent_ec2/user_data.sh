#!/bin/bash
set -euo pipefail

AGENT_NAME="${agent_name}"
AWS_REGION="${aws_region}"
CLOUDWATCH_LOG_GROUP="${cloudwatch_log_group}"
BEDROCK_MODEL_ID="${bedrock_model_id}"
GATEWAY_PORT="${gateway_port}"
TELEGRAM_BOT_TOKEN="${telegram_bot_token}"
GATEWAY_AUTH_TOKEN="${gateway_auth_token}"
ENABLE_HOST_METRICS="${enable_host_metrics}"
HOST_METRICS_NAMESPACE="${host_metrics_namespace}"
HOST_METRICS_INTERVAL="${host_metrics_interval}"

AGENT_HOME="/home/$AGENT_NAME"
NPM_GLOBAL="$AGENT_HOME/.npm-global"
OPENCLAW_DIR="$AGENT_HOME/.openclaw"

exec > >(tee -a /var/log/user-data.log)
exec 2>&1
echo "==== OpenClaw Agent Bootstrap Started at $(date) ===="
echo "Agent: $AGENT_NAME | Region: $AWS_REGION | Model: $BEDROCK_MODEL_ID"

echo "[1/7] Updating system packages..."
dnf update -y
dnf install -y amazon-cloudwatch-agent git jq dnf-automatic
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer

echo "[2/7] Installing Node.js 22..."
curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
dnf install -y nodejs
echo "  Node.js $(node -v) | npm $(npm -v)"

echo "[3/7] Creating agent user: $AGENT_NAME..."
id -u "$AGENT_NAME" &>/dev/null || useradd -m -s /bin/bash "$AGENT_NAME"
mkdir -p "$NPM_GLOBAL"
chown -R "$AGENT_NAME:$AGENT_NAME" "$NPM_GLOBAL"

cat > "$AGENT_HOME/.npmrc" <<NPMRC
prefix=$NPM_GLOBAL
NPMRC
chown "$AGENT_NAME:$AGENT_NAME" "$AGENT_HOME/.npmrc"

cat >> "$AGENT_HOME/.bashrc" <<'BASHRC_STATIC'
export PATH="$HOME/.npm-global/bin:$PATH"
export AWS_PROFILE=default
BASHRC_STATIC
cat >> "$AGENT_HOME/.bashrc" <<BASHRC_REGION
export AWS_REGION=$AWS_REGION
BASHRC_REGION

mkdir -p "$AGENT_HOME/.aws"
cat > "$AGENT_HOME/.aws/config" <<AWSCONFIG
[default]
region = $AWS_REGION
AWSCONFIG
chown -R "$AGENT_NAME:$AGENT_NAME" "$AGENT_HOME/.aws"
loginctl enable-linger "$AGENT_NAME"

echo "[4/7] Installing OpenClaw CLI..."
su - "$AGENT_NAME" -c "npm install -g openclaw@latest"
echo "  $(su - "$AGENT_NAME" -c "openclaw --version" 2>&1 | head -1)"

echo "[5/7] Creating OpenClaw config..."
su - "$AGENT_NAME" -c "mkdir -p $OPENCLAW_DIR"

cat > "$OPENCLAW_DIR/openclaw.json" <<OCCONFIG
{
  "models": {
    "providers": {
      "amazon-bedrock": {
        "baseUrl": "https://bedrock-runtime.$AWS_REGION.amazonaws.com",
        "api": "bedrock-converse-stream",
        "auth": "aws-sdk",
        "models": [
          {"id":"anthropic.claude-3-7-sonnet-20250219-v1:0","name":"Claude 3.7 Sonnet","reasoning":true,"input":["text","image"],"contextWindow":200000,"maxTokens":8192},
          {"id":"eu.anthropic.claude-opus-4-6-v1:0","name":"Claude Opus 4.6","reasoning":true,"input":["text","image"],"contextWindow":200000,"maxTokens":8192},
          {"id":"anthropic.claude-3-haiku-20240307-v1:0","name":"Claude 3 Haiku","reasoning":false,"input":["text","image"],"contextWindow":200000,"maxTokens":4096}
        ]
      }
    },
    "bedrockDiscovery": {"enabled":true,"region":"$AWS_REGION"}
  },
  "agents": {
    "defaults": {
      "model": {"primary":"amazon-bedrock/anthropic.claude-3-7-sonnet-20250219-v1:0"},
      "maxConcurrent": 4,
      "workspace": "$OPENCLAW_DIR/workspace"
    }
  },
  "logging": {"file":"$OPENCLAW_DIR/logs/openclaw.log"},
  "gateway": {
    "mode": "local",
    "port": $GATEWAY_PORT,
    "bind": "loopback",
    "auth": {"mode":"token","token":"$GATEWAY_AUTH_TOKEN"}
  },
  "channels": {
    "telegram": {"enabled":true,"botToken":"$TELEGRAM_BOT_TOKEN","dmPolicy":"pairing"}
  },
  "plugins": {"entries":{"telegram":{"enabled":true}}}
}
OCCONFIG

chown -R "$AGENT_NAME:$AGENT_NAME" "$OPENCLAW_DIR"
chmod 700 "$OPENCLAW_DIR"

echo "[6/7] Installing gateway service..."
su - "$AGENT_NAME" -c "mkdir -p $OPENCLAW_DIR/workspace $OPENCLAW_DIR/agents/main/sessions $OPENCLAW_DIR/logs"

cat > /etc/systemd/system/openclaw-gateway.service <<SYSTEMD
[Unit]
Description=OpenClaw Gateway - $AGENT_NAME
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=$AGENT_NAME
Group=$AGENT_NAME
WorkingDirectory=$AGENT_HOME
Environment=PATH=$NPM_GLOBAL/bin:/usr/local/bin:/usr/bin:/bin
Environment=AWS_PROFILE=default
Environment=AWS_REGION=$AWS_REGION
Environment=HOME=$AGENT_HOME
Environment=NODE_ENV=production
ExecStart=$NPM_GLOBAL/bin/openclaw gateway
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-gateway
NoNewPrivileges=true
PrivateTmp=true
[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable openclaw-gateway.service
systemctl start openclaw-gateway.service

cat > /etc/profile.d/openclaw-gateway-aliases.sh <<'ALIASES'
alias oc-status='sudo systemctl status openclaw-gateway'
alias oc-start='sudo systemctl start openclaw-gateway'
alias oc-restart='sudo systemctl restart openclaw-gateway'
ALIASES
chmod 644 /etc/profile.d/openclaw-gateway-aliases.sh

echo "[7/7] Configuring CloudWatch agent..."
mkdir -p "$OPENCLAW_DIR/logs"
chown "$AGENT_NAME:$AGENT_NAME" "$OPENCLAW_DIR/logs"
chmod 755 "$OPENCLAW_DIR/logs"

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWCONFIG
{
$( if [ "$ENABLE_HOST_METRICS" = "true" ]; then cat <<METRICS
  "metrics": {
    "namespace": "$HOST_METRICS_NAMESPACE",
    "metrics_collected": {
      "mem": {"measurement":["mem_used_percent","mem_used","mem_available"],"metrics_collection_interval":$HOST_METRICS_INTERVAL},
      "disk": {"measurement":["disk_used_percent","disk_used","disk_free"],"resources":["/"],"metrics_collection_interval":$HOST_METRICS_INTERVAL},
      "cpu": {"measurement":["cpu_usage_idle","cpu_usage_user","cpu_usage_system"],"totalcpu":true,"metrics_collection_interval":$HOST_METRICS_INTERVAL},
      "swap": {"measurement":["swap_used_percent"],"metrics_collection_interval":$HOST_METRICS_INTERVAL}
    },
    "append_dimensions": {"InstanceId":"\$${aws:InstanceId}","InstanceType":"\$${aws:InstanceType}"}
  },
METRICS
fi )
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {"file_path":"$OPENCLAW_DIR/logs/openclaw*.log","log_group_name":"$CLOUDWATCH_LOG_GROUP","log_stream_name":"{instance_id}/openclaw","timezone":"UTC","timestamp_format":"%Y-%m-%dT%H:%M:%S.%f%z"},
          {"file_path":"/var/log/user-data.log","log_group_name":"$CLOUDWATCH_LOG_GROUP","log_stream_name":"{instance_id}/user-data","timezone":"UTC"},
          {"file_path":"/var/log/cloud-init-output.log","log_group_name":"$CLOUDWATCH_LOG_GROUP","log_stream_name":"{instance_id}/cloud-init","timezone":"UTC"}
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl enable amazon-cloudwatch-agent

echo "==== Bootstrap Complete at $(date) ===="
echo "Agent: $AGENT_NAME | Config: $OPENCLAW_DIR/openclaw.json | Service: openclaw-gateway.service"
echo "Gateway: http://localhost:$GATEWAY_PORT"
touch /var/lib/cloud/instance/openclaw-ready
