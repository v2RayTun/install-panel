# V2RayTun Panel — Universal Installer

One-command installer for V2RayTun Panel. No tokens, no source code, no manual configuration — just run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/v2RayTun/install-panel/main/install.sh)
```

The installer asks only for the **panel domain** (e.g. `panel.example.com`) — it must already point to this server's IP via a DNS A-record.

Everything else is automated:

- Detects the OS and installs Docker + Docker Compose
- Pulls pre-built images from the public registry `docker-registry.v2raytun.com`
- Generates strong random secrets for PostgreSQL, RabbitMQ and JWT
- Brings up Postgres, Redis, RabbitMQ, backend, frontend
- Configures Caddy reverse proxy with automatic Let's Encrypt SSL
- Runs inside a `tmux` session so SSH disconnects don't break the install

After install, open `https://your-domain/auth/login` and create the first admin account.

---

## Requirements

- Linux server with **root access** (Ubuntu 22.04+, Debian 12+, Fedora, RHEL, Alma/Rocky, Alpine, Arch)
- **2 vCPU / 2 GB RAM** for the panel server, **1 vCPU / 512 MB RAM** per node
- A domain pointed at the panel server (`A` record), with ports **80** and **443** open

---

## Adding a node

On a separate Linux server:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/v2RayTun/install-panel/main/install.sh)
```

In the menu choose **2) Install Node**, then pick the recommended option:

- **Paste docker-compose from the panel** — in the panel UI go to *Nodes → Create Node*, fill in the fields, click *Create*, copy the docker-compose snippet, paste it into the installer. This includes mTLS certificates.

The node should appear as *Connected* in the panel within ~60 seconds. The agent port (default `2222`) must be reachable from the panel's server.

The agent port answers only the panel's addresses (and the server itself with its Docker containers) once **System → Panel → Panel IPs for nodes** is set: the panel writes them into the compose (`PANEL_IPS`) and the agent keeps the port to them itself (a kernel rule of its own, so a scanner sees it filtered). When the compose has no `PANEL_IPS`, the installer takes them from `V2RAYTUN_PANEL_IP` (comma-separated, at least one IPv4: the agent port takes IPv4 only) or asks. After the start it reports the rule as the agent does (`agent-port status`: the chain, and INPUT jumping to it first). With ufw active it lets the port through ufw for the agent to decide, or, when the agent cannot set its rule, keeps the port to the panel in ufw, and says what ufw really does.

Moving the panel to another address: add the new address to **Panel IPs for nodes** before the move, and the panel sends it to the nodes itself. If it has moved already, stop the old panel, put the new address in the list and run on each node `docker exec $(docker ps -qf name=^v2raytunpanel-node | head -1) agent-port allow <new panel IP>`: the new panel gets in and sends its list, the old one does not. ufw rules the installer set for a node without the agent's rule keep the old address: change them too.

---

## Updating

After a new release:

```bash
v2raytunsetup update         # update panel
v2raytunsetup update node    # update node
```

Pulls fresh images and restarts containers. Data and configuration are preserved.

---

## Useful commands

```bash
v2raytunsetup                  # interactive menu
v2raytunsetup status           # show containers
v2raytunsetup logs             # tail backend logs
v2raytunsetup logs frontend    # tail frontend logs
v2raytunsetup backup           # dump postgres + redis to /var/backups/v2raytunpanel
v2raytunsetup restore          # restore from a backup
v2raytunsetup attach           # reattach to running tmux setup session
v2raytunsetup resume           # restart containers after a reboot or crash
v2raytunsetup help             # show all options
```

---

## Non-interactive (CI / automation)

Pre-fill all prompts via environment variables:

```bash
sudo \
  V2RAYTUN_PANEL_DOMAIN=panel.example.com \
  V2RAYTUN_SUB_DOMAIN=panel.example.com \
  V2RAYTUN_ACTION=install-panel \
  bash <(curl -fsSL https://raw.githubusercontent.com/v2RayTun/install-panel/main/install.sh)
```

Available variables:

| Variable | Description |
|---|---|
| `V2RAYTUN_REGISTRY` | Docker registry hostname (default `docker-registry.v2raytun.com`) |
| `V2RAYTUN_VERSION` | Image tag to pull (default `1.0.10`) |
| `V2RAYTUN_PANEL_DOMAIN` | Panel domain — skips prompt |
| `V2RAYTUN_SUB_DOMAIN` | Subscription page domain (defaults to panel domain) |
| `V2RAYTUN_ACTION` | `install-panel` / `install-node` / `update-panel` / `update-node` |
| `V2RAYTUNSETUP_REPO` | Source for helper scripts (default `v2RayTun/install-panel`) |
| `V2RAYTUNSETUP_BRANCH` | Branch (default `main`) |

---

## File layout after install

| Path | Description |
|---|---|
| `/opt/v2raytunpanel/docker/` | Panel docker-compose, `.env` and volumes |
| `/opt/v2raytunpanel/caddy/` | Caddy reverse proxy + TLS certificates |
| `/opt/v2raytunpanel-node/` | Node docker-compose and `.env` |
| `/opt/v2raytunpanel-setup/` | Cached installer scripts (used by `v2raytunsetup`) |
| `/var/backups/v2raytunpanel/` | Database / redis / env backups |
| `/usr/local/bin/v2raytunsetup` | Global CLI entrypoint |

---

## Troubleshooting

**Backend stays unhealthy.** Check the logs:

```bash
v2raytunsetup logs backend
```

Common issues: domain not yet pointing at the server (Caddy can't issue TLS), `.env` missing required values, port 80/443 blocked by firewall.

**SSH dropped during install.** Reconnect, then run `v2raytunsetup attach` to reattach to the running tmux session.

---

## Security notes

- Source code stays in a private repository. The installer only pulls pre-built Docker images.
- Database, RabbitMQ, JWT and admin secrets are generated locally during install and never leave the machine.
- Backups are stored only on the same machine in `/var/backups/v2raytunpanel/`.
- The installer chmods `.env` to `600` so it's readable only by root.

---

## License

This installer is MIT-licensed. The panel itself, distributed as Docker images, is proprietary software.
