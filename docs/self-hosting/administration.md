# Administration

## cairn-ctl

`cairn-ctl` is the operator CLI installed at `/usr/local/bin/cairn-ctl`. It wraps Docker Compose commands and provides shortcuts for common tasks.

All commands operate on the deploy directory at `/opt/cairn` (override with the `CAIRN_DIR` environment variable).

### Command reference

| Command | Description |
|---------|-------------|
| `cairn-ctl status` | Show service status, health check result, and deploy directory |
| `cairn-ctl start` | Start all services |
| `cairn-ctl stop` | Stop all services |
| `cairn-ctl restart` | Restart all services |
| `cairn-ctl logs [service]` | Follow logs for all services, or a specific one (e.g., `server`, `sfu`, `postgres`) |
| `cairn-ctl upgrade` | Pull latest images, create a backup, restart with rolling updates, run migrations |
| `cairn-ctl rollback` | Restore the database from the most recent backup (prompts for confirmation) |
| `cairn-ctl backup` | Create a backup of the database, uploads, and federation keys |
| `cairn-ctl restore <path>` | Restore from a specific backup directory (prompts for confirmation) |
| `cairn-ctl config` | Show all configuration values |
| `cairn-ctl config <key>` | Show a single configuration value |
| `cairn-ctl config <key> <value>` | Set a configuration value (restart required to take effect) |
| `cairn-ctl user create <username> <password>` | Create a user account |
| `cairn-ctl federation list` | List known federation nodes and their status |

## Backups

### What gets backed up

| Component | Contents |
|-----------|----------|
| Database | Full PostgreSQL dump (`pg_dump -Fc`) |
| Uploads | User-uploaded files from `/app/priv/uploads` |
| Keys | Federation signing keys from `/app/priv/keys` |

### Manual backup

```sh
cairn-ctl backup
```

Backups are saved to `/opt/cairn/backups/cairn-backup-YYYYMMDD-HHMMSS/`.

### Restore

```sh
cairn-ctl restore /opt/cairn/backups/cairn-backup-20250115-143022
cairn-ctl restart
```

The restore command replaces the current database. A restart is needed afterward.

### Automated backups with cron

```sh
# Daily backup at 3 AM, keep 30 days
echo "0 3 * * * root cairn-ctl backup" | sudo tee /etc/cron.d/cairn-backup

# Prune backups older than 30 days
echo "30 3 * * * root find /opt/cairn/backups -maxdepth 1 -mtime +30 -exec rm -rf {} +" | sudo tee -a /etc/cron.d/cairn-backup
```

## Upgrading

### Using cairn-ctl

```sh
cairn-ctl upgrade
```

This performs a full upgrade cycle:

1. Creates a pre-upgrade backup
2. Pulls latest Docker images
3. Restarts the server (rolling — no full downtime)
4. Waits for health check
5. Runs database migrations
6. Restarts the SFU

### Manual upgrade

```sh
cd /opt/cairn
docker compose pull
docker compose up -d --no-deps server
# Wait for health
docker compose exec -T server bin/cairn eval "Cairn.Release.migrate()"
docker compose up -d --no-deps sfu
```

### Pinning a version

By default, services pull `latest`. To pin to a specific release:

```sh
cairn-ctl config CAIRN_IMAGE ghcr.io/morelandjo/cairn-server:v0.1.0
cairn-ctl config SFU_IMAGE ghcr.io/morelandjo/cairn-sfu:v0.1.0
cairn-ctl restart
```

## Ansible playbooks

For managing multiple servers or automating deployments, Ansible playbooks are provided in `deploy/ansible/`.

### Setup

Create an inventory file from the example:

```sh
cp deploy/ansible/inventory.example.ini deploy/ansible/inventory.ini
```

Edit `inventory.ini` with your server's IP and domain:

```ini
[cairn]
cairn-server ansible_host=203.0.113.10 ansible_user=root

[cairn:vars]
cairn_domain=cairn.example.com
deploy_dir=/opt/cairn
```

### Available playbooks

| Playbook | Description | Usage |
|----------|-------------|-------|
| `setup.yml` | Provision a fresh server (Docker, firewall, swap, cairn user) | `ansible-playbook -i inventory.ini setup.yml` |
| `deploy.yml` | Deploy Cairn (copy compose/env, pull images, start, migrate) | `ansible-playbook -i inventory.ini deploy.yml` |
| `backup.yml` | Create a backup (database, uploads, keys) with 30-day retention | `ansible-playbook -i inventory.ini backup.yml` |
| `update.yml` | Update Cairn (backup, pull images, rolling restart, migrate) | `ansible-playbook -i inventory.ini update.yml` |

### Typical workflow

```sh
# First time: provision the server, then deploy
ansible-playbook -i inventory.ini setup.yml
ansible-playbook -i inventory.ini deploy.yml

# Later: update to latest version
ansible-playbook -i inventory.ini update.yml
```

## Monitoring

Cairn exposes Prometheus metrics via PromEx. To enable monitoring, connect a Prometheus instance to scrape the server's metrics endpoint and import the provided Grafana dashboards.

## Logs

View logs for all services:

```sh
cairn-ctl logs
```

View logs for a specific service:

```sh
cairn-ctl logs server
cairn-ctl logs sfu
cairn-ctl logs postgres
```

Every HTTP request includes a correlation ID in the `x-request-id` header and in log metadata, which can be used to trace requests across services.
