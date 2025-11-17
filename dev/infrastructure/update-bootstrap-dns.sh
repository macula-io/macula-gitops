#!/usr/bin/env bash
# Remove bootstrap.macula.local from dnsmasq (should be managed by PowerDNS)
# Run with: sudo ./update-bootstrap-dns.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

echo "Removing bootstrap.macula.local from dnsmasq..."
sed -i '/bootstrap.macula.local/d' /etc/dnsmasq.d/macula.conf

echo "Restarting dnsmasq..."
systemctl restart dnsmasq

sleep 2

echo ""
echo "DNS resolution test:"
dig +short bootstrap.macula.local @127.0.0.1

echo ""
echo "✓ Done! bootstrap.macula.local is now managed by PowerDNS"
