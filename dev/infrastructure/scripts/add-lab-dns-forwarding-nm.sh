#!/bin/bash
# Add DNS forwarding for .lab domain to PowerDNS
# For NetworkManager-managed dnsmasq

set -e

NM_DNSMASQ_DIR="/etc/NetworkManager/dnsmasq.d"
POWERDNS_IP="172.22.0.10"

# Check if NetworkManager dnsmasq.d exists
if [ ! -d "$NM_DNSMASQ_DIR" ]; then
    echo "Creating $NM_DNSMASQ_DIR"
    mkdir -p "$NM_DNSMASQ_DIR"
fi

# Check if already configured
if [ -f "$NM_DNSMASQ_DIR/lab-dns.conf" ]; then
    echo "DNS forwarding for .lab already configured"
    cat "$NM_DNSMASQ_DIR/lab-dns.conf"
    exit 0
fi

echo "Adding DNS forwarding for .lab to PowerDNS at $POWERDNS_IP"

# Create config file
cat > "$NM_DNSMASQ_DIR/lab-dns.conf" << EOF
# Forward .lab domain queries to PowerDNS (Docker: 172.22.0.10)
server=/lab/$POWERDNS_IP
EOF

echo "Restarting NetworkManager to reload dnsmasq..."
systemctl restart NetworkManager

sleep 2

echo "Testing DNS resolution..."
dig console.beam01.lab +short
