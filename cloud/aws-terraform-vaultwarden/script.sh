#!/usr/bin/env bash
set -euo pipefail

# Expects environment variables from user_data:
#   DOMAIN    (e.g., thebestvault.ddns.net)
#   EMAIL     (e.g., you@example.com)
#   EIP       (Elastic IP)
#   NOIP_USER (e.g., group:account@noip.com)
#   NOIP_PASS (No-IP password)

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
EIP="${EIP:-}"
NOIP_USER="${NOIP_USER:-}"
NOIP_PASS="${NOIP_PASS:-}"

# Basic updates and tools
apt-get update
apt-get -y upgrade
apt-get -y install ca-certificates curl gnupg lsb-release

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Vaultwarden data
mkdir -p /opt/vaultwarden
chmod 700 /opt/vaultwarden

# Run Vaultwarden container on localhost:8080 (reverse-proxied by Apache)
docker run -d --name vaultwarden \
  --restart unless-stopped \
  -v /opt/vaultwarden:/data \
  -e WEBSOCKET_ENABLED=true \
  -p 127.0.0.1:8080:80 \
  vaultwarden/server:latest

# Apache + Certbot
apt-get -y install apache2 python3-certbot-apache
a2enmod proxy proxy_http headers ssl

cat >/etc/apache2/sites-available/${DOMAIN}.conf <<APACHECONF
<VirtualHost *:80>
  ServerName ${DOMAIN}
  ProxyPreserveHost On
  ProxyPass / http://127.0.0.1:8080/
  ProxyPassReverse / http://127.0.0.1:8080/
  RequestHeader set X-Forwarded-Proto "http"
  RequestHeader set X-Forwarded-For "%{REMOTE_ADDR}s"
</VirtualHost>
APACHECONF

a2ensite ${DOMAIN}.conf
systemctl reload apache2

# ----------------------------------------------
# MANUAL DNS CONFIGURATION + NO-IP DUC SECTION
# ----------------------------------------------
echo ""
echo "  Please go to your No-IP dashboard and create this record now:"
echo "   Hostname: ${DOMAIN}"
echo "   IP: $(curl -s ifconfig.me)"

echo ""
echo "=============================================="
echo " Installing and connecting to No-IP DUC client"
echo "=============================================="

# Modern installation method (works on Ubuntu 22.04 / 24.04)
cd /tmp
wget --content-disposition https://www.noip.com/download/linux/latest
tar xf noip-duc_*.tar.gz
cd noip-duc_*/binaries
sudo apt install -y ./noip-duc_*_amd64.deb

# Register this instance with No-IP
sudo noip-duc -u "${NOIP_USER}" -p "${NOIP_PASS}" --once

echo " No-IP DUC registration complete."
echo ""
# ----------------------------------------------

# Wait until DNS (A) for DOMAIN points to this instance's Elastic IP, then issue cert
if [[ -n "${EIP}" ]]; then
  echo "Waiting for ${DOMAIN} to resolve to ${EIP} before running certbot..."
  for i in {1..120}; do
    RESOLVED=$(getent ahostsv4 "${DOMAIN}" | awk '{print $1}' | head -n1 || true)
    if [[ "${RESOLVED:-}" == "${EIP}" ]]; then
      echo "DNS OK (${DOMAIN} -> ${EIP}). Running certbot..."
      certbot --apache -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" || true
      break
    fi
    sleep 5
  done
else
  echo "EIP not provided; skipping DNS wait and certbot."
fi

echo "Bootstrap complete."

