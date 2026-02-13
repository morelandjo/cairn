# Reverse Proxy

Cairn listens on HTTP (default port 4000). You need a reverse proxy to terminate TLS and expose the instance on ports 80/443.

## Caddy (recommended)

Caddy automatically obtains and renews Let's Encrypt certificates.

Create `/etc/caddy/Caddyfile`:

```caddyfile
cairn.example.com {
    reverse_proxy localhost:4000
}
```

Reload Caddy:

```sh
sudo systemctl reload caddy
```

That's it — Caddy handles TLS certificates, HTTP/2, and WebSocket upgrades automatically.

## nginx + Let's Encrypt

Install nginx and Certbot:

```sh
# Debian/Ubuntu
sudo apt install nginx certbot python3-certbot-nginx

# Fedora
sudo dnf install nginx certbot python3-certbot-nginx
```

Create `/etc/nginx/sites-available/cairn`:

```nginx
server {
    listen 80;
    server_name cairn.example.com;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (required for real-time features)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Increase timeouts for long-lived WebSocket connections
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

Enable the site and obtain a certificate:

```sh
sudo ln -s /etc/nginx/sites-available/cairn /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d cairn.example.com
```

Certbot will modify the config to add TLS and set up auto-renewal.

## WebSocket paths

Cairn uses WebSocket connections at `/socket/websocket` for real-time messaging. Your reverse proxy must support WebSocket upgrades. Both the Caddy and nginx configurations above handle this correctly.

## Voice and video ports

The SFU and TURN server use `network_mode: host`, so they bind directly to the host's network interfaces — no proxy configuration is needed for them. Make sure these ports are open in your firewall:

| Port | Protocol | Service |
|------|----------|---------|
| 3478 | TCP + UDP | TURN signaling |
| 40000–40100 | UDP | SFU media (WebRTC) |
| 49152–49200 | UDP | TURN relay |

The install script configures UFW rules for these automatically. If you manage your firewall manually, ensure these ports are open.

## Cloudflare

If you use Cloudflare as a proxy, note that Cloudflare does not proxy arbitrary UDP traffic on free plans. Voice/video will connect directly to your server IP via TURN, bypassing Cloudflare. HTTP and WebSocket traffic will work through Cloudflare normally.

Set Cloudflare SSL mode to **Full (strict)** if your origin has a valid certificate.
