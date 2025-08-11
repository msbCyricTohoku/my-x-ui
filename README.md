# x-ui

x-ui is an xray panel that supports multiple protocols and multiple users.

## Features

- System status monitoring
- Multi-user and multi-protocol support with web-based management
- Supported protocols: vmess, vless, trojan, shadowsocks, dokodemo-door, socks, http
- Flexible transport configuration
- Traffic statistics with limits and expiration settings
- Customizable xray configuration templates
- HTTPS access to the panel (bring your own domain and SSL certificate)
- One-click SSL certificate application and automatic renewal
- More advanced options available in the panel

## Installation & Upgrade

```bash
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
```

## Manual Installation & Upgrade

1. Download the latest archive from https://github.com/vaxilu/x-ui/releases (choose `amd64` if unsure).
2. Upload the archive to the server's `/root/` directory and log in as `root`.
3. Run the following commands:

```bash
cd /root/
rm x-ui/ /usr/local/x-ui/ /usr/bin/x-ui -rf
tar zxvf x-ui-linux-amd64.tar.gz
chmod +x x-ui/x-ui x-ui/bin/xray-linux-* x-ui/x-ui.sh
cp x-ui/x-ui.sh /usr/bin/x-ui
cp -f x-ui/x-ui.service /etc/systemd/system/
mv x-ui/ /usr/local/
systemctl daemon-reload
systemctl enable x-ui
systemctl restart x-ui
```

## Docker Installation

```bash
curl -fsSL https://get.docker.com | sh
mkdir x-ui && cd x-ui
docker run -itd --network=host \
    -v $PWD/db/:/etc/x-ui/ \
    -v $PWD/cert/:/root/cert/ \
    --name x-ui --restart=unless-stopped \
    enwaiax/x-ui:latest
```

## SSL Certificate Application

The script includes SSL certificate application functionality using Cloudflare DNS API. Ensure you know:

- Cloudflare registration email
- Cloudflare Global API Key
- Domain resolved to the server via Cloudflare

Certificates are installed to `/root/cert` and use Let's Encrypt by default.

## Telegram Bot (WIP)

x-ui can send notifications via a Telegram bot for traffic usage, login alerts, and more. Set the bot parameters in the panel backend.

## Recommended Systems

- CentOS 7+
- Ubuntu 16+
- Debian 8+

## Migration from v2-ui

Install the latest x-ui on the server running v2-ui and run:

```bash
x-ui v2-ui
```

After migration, stop v2-ui and restart x-ui to avoid port conflicts.

