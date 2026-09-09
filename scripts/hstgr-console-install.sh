#!/usr/bin/env bash
# Hostinger web console: paste and run as root.
# Public host: srv1790270.hstgr.cloud
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

DOMAIN=srv1790270.hstgr.cloud
ACME_EMAIL=zlalxp@gmail.com
PUBLIC_BASE_URL=https://srv1790270.hstgr.cloud
AGENT_TOKEN=$(openssl rand -hex 32)

echo "==> stop default web on 80/443 if any"
systemctl stop apache2 nginx 2>/dev/null || true
systemctl disable apache2 nginx 2>/dev/null || true
fuser -k 80/tcp 443/tcp 2>/dev/null || true

echo "==> packages"
apt-get update
apt-get install -y python3 python3-venv python3-pip git curl ca-certificates \
  debian-keyring debian-archive-keyring apt-transport-https gnupg

if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi

echo "==> node 22 if missing"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

echo "==> dirs"
install -d -m 0755 /opt/cross-agent/workspace /opt/cross-agent/gateway /opt/src
cd /opt/src
if [[ ! -d cross-agent-gateway/.git ]]; then
  git clone https://github.com/zlalxp/cross-agent-gateway.git || mkdir -p cross-agent-gateway
fi

if [[ -d /opt/src/cross-agent-gateway/gateway ]]; then
  cp -a /opt/src/cross-agent-gateway/gateway/. /opt/cross-agent/gateway/
fi

if [[ ! -f /opt/cross-agent/gateway/server.py ]]; then
  echo "ERROR: gateway/server.py missing. Upload the zip to /opt/src and unpack." >&2
  exit 1
fi

if [[ ! -d /opt/cross-agent/.venv ]]; then
  python3 -m venv /opt/cross-agent/.venv
fi
/opt/cross-agent/.venv/bin/pip install -U pip
if [[ -f /opt/cross-agent/gateway/requirements.txt ]]; then
  /opt/cross-agent/.venv/bin/pip install -r /opt/cross-agent/gateway/requirements.txt
else
  /opt/cross-agent/.venv/bin/pip install 'fastmcp>=2.10.0' uvicorn httpx python-dotenv
fi

cat >/opt/cross-agent/.env <<EOF
PUBLIC_BASE_URL=${PUBLIC_BASE_URL}
AGENT_TOKEN=${AGENT_TOKEN}
GATEWAY_HOST=127.0.0.1
GATEWAY_PORT=8787
WORKSPACE=/opt/cross-agent/workspace
DISPATCH_TIMEOUT=600
MAX_DEPTH=1
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
EOF
chmod 600 /opt/cross-agent/.env

mkdir -p /etc/caddy
cat >/etc/caddy/Caddyfile <<EOF
${DOMAIN} {
	encode gzip
	@health path /healthz /
	handle @health {
		reverse_proxy 127.0.0.1:8787
	}
	@authed header Authorization "Bearer ${AGENT_TOKEN}"
	handle @authed {
		reverse_proxy 127.0.0.1:8787
	}
	respond "unauthorized" 401
}
EOF

cat >/etc/systemd/system/cross-agent-gateway.service <<'EOF'
[Unit]
Description=Cross-agent MCP gateway
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/cross-agent/gateway
EnvironmentFile=/opt/cross-agent/.env
Environment=PATH=/root/.local/bin:/root/.claude/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
ExecStart=/opt/cross-agent/.venv/bin/python /opt/cross-agent/gateway/server.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

echo "==> CLIs"
curl -fsSL https://claude.ai/install.sh | bash || true
npm install -g @openai/codex || true
curl -fsSL https://x.ai/cli/install.sh | bash || true
export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"

systemctl daemon-reload
systemctl enable --now cross-agent-gateway
systemctl enable --now caddy
systemctl restart caddy

echo
echo "===== SAVE THIS TOKEN ====="
echo "$AGENT_TOKEN"
echo "MCP URL: ${PUBLIC_BASE_URL}/mcp"
echo "Health:  curl -fsS ${PUBLIC_BASE_URL}/healthz"
echo
echo "Next logins on this VPS:"
echo "  export PATH=\"\$HOME/.local/bin:\$HOME/.claude/bin:\$PATH\""
echo "  claude"
echo "  codex login"
echo "  grok login --device-auth"
echo "============================"
