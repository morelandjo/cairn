# Advanced Installation

These guides cover manual configuration, custom proxy setups, and federation. If you used the [install script](quickstart.md), most of this was handled automatically.

## Non-interactive install

You can skip the wizard by providing a pre-filled `.env` file:

```sh
curl -sSL https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/install.sh | sudo bash -s -- --env /path/to/.env
```

Or supply a custom Docker Compose file:

```sh
curl -sSL https://raw.githubusercontent.com/morelandjo/cairn/main/deploy/install.sh | sudo bash -s -- --config /path/to/docker-compose.yml
```

See [Configuration](configuration.md) for all available `.env` variables.

## Guides

- [Configuration](configuration.md) — environment variables, storage backends, SSL
- [Reverse Proxy](reverse-proxy.md) — Caddy and nginx configs with TLS (for manual setup)
- [Federation](federation.md) — connect your instance to others
