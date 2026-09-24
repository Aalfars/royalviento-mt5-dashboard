#!/bin/bash
# ==============================================================================
# Setup Custom Domain (trading.aranya.my.id) via Cloudflare Zero Trust Tunnel
# ==============================================================================
set -e

TUNNEL_TOKEN="$1"

if [ -z "$TUNNEL_TOKEN" ]; then
    echo "======================================================================"
    echo "CARA PENGGUNAAN:"
    echo "  /root/dashboard/scripts/setup_domain.sh <CLOUDFLARE_TUNNEL_TOKEN>"
    echo ""
    echo "Langkah mendapatkan token di Cloudflare Dashboard:"
    echo "1. Buka https://one.dash.cloudflare.com (Cloudflare Zero Trust)"
    echo "2. Masuk ke: Networks -> Tunnels"
    echo "3. Klik 'Add a tunnel' -> pilih 'Cloudflared' -> beri nama (misal: trading-vps)"
    echo "4. Pada bagian 'Install and run a connector', salin Token (string panjang)"
    echo "5. Pada tab 'Public Hostnames', tambahkan:"
    echo "   - Subdomain: trading"
    echo "   - Domain: aranya.my.id"
    echo "   - Type: HTTP"
    echo "   - URL: localhost:5000"
    echo "6. Jalankan script ini dengan token tersebut:"
    echo "   /root/dashboard/scripts/setup_domain.sh eyJhIjoi..."
    echo "======================================================================"
    exit 1
fi

echo "=== MENGHUBUNGKAN CLOUDFLARE TUNNEL KE DOMAIN trading.aranya.my.id ==="

cat << EOF > /etc/systemd/system/cloudflared-tunnel.service
[Unit]
Description=Cloudflare Tunnel for MT5 Dashboard (trading.aranya.my.id)
After=network.target mt5-dashboard.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel run --token $TUNNEL_TOKEN
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart cloudflared-tunnel
systemctl status cloudflared-tunnel --no-pager

echo ""
echo "======================================================================"
echo "BERHASIL! Cloudflare Tunnel untuk trading.aranya.my.id telah aktif!"
echo "Dashboard sekarang dapat diakses secara permanen melalui:"
echo "👉 https://trading.aranya.my.id"
echo "======================================================================"
