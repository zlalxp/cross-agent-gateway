#!/usr/bin/env bash
set -euo pipefail
if [[ ${EUID:-0} -ne 0 ]]; then echo run as root >&2; exit 1; fi
DOMAIN="${DOMAIN:-}"; AGENT_TOKEN="${AGENT_TOKEN:-}"; ACME_EMAIL="${ACME_EMAIL:-}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://${DOMAIN}}"
if [[ -z "$DOMAIN" || -z "$AGENT_TOKEN" || -z "$ACME_EMAIL" ]]; then echo "Set DOMAIN, AGENT_TOKEN, ACME_EMAIL" >&2; exit 1; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip git curl ca-certificates debian-keyring debian-archive-keyring apt-transport-https
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update && apt-get install -y caddy
fi
SRC="$(cd "$(dirname "$0")/.." && pwd)"
install -d -m 0755 /opt/cross-agent/workspace /opt/cross-agent/gateway
cp -a "$SRC/gateway/." /opt/cross-agent/gateway/
install -m 0644 "$SRC/systemd/cross-agent-gateway.service" /etc/systemd/system/cross-agent-gateway.service
[[ -d /opt/cross-agent/.venv ]] || python3 -m venv /opt/cross-agent/.venv
/opt/cross-agent/.venv/bin/pip install -U pip
/opt/cross-agent/.venv/bin/pip install -r /opt/cross-agent/gateway/requirements.txt
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
cp "$SRC/caddy/Caddyfile" /etc/caddy/Caddyfile
cat >/etc/caddy/env <<EOF
DOMAIN=${DOMAIN}
AGENT_TOKEN=${AGENT_TOKEN}
EOF
chmod 600 /etc/caddy/env
mkdir -p /etc/systemd/system/caddy.service.d
cat >/etc/systemd/system/caddy.service.d/override.conf <<'EOF'
[Service]
EnvironmentFile=/etc/caddy/env
EOF
bash "$SRC/scripts/install-clis.sh"
mkdir -p /etc/systemd/system/cross-agent-gateway.service.d
cat >/etc/systemd/system/cross-agent-gateway.service.d/path.conf <<'EOF'
[Service]
Environment=PATH=/root/.local/bin:/root/.claude/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
EOF
systemctl daemon-reload
systemctl enable --now cross-agent-gateway caddy
echo Gateway at ${PUBLIC_BASE_URL}/mcp
