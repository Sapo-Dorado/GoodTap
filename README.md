# GoodTap

A Phoenix LiveView application.

## Development

```bash
mix setup        # install deps, create and migrate DB, build assets
mix phx.server   # start the dev server at localhost:4000
```

Or inside IEx:

```bash
iex -S mix phx.server
```

## Production deployment

The repo includes a Nix flake that builds the app and manages the full stack as a single NixOS host:

- **PostgreSQL** — managed as a systemd service, data persisted in `/var/lib/postgresql`
- **GoodTap** — Phoenix release built by Nix, runs as a systemd service on port 4000
- **nginx** — reverse proxy on ports 80/443, terminates SSL (port 4000 is not publicly exposed)
- **Let's Encrypt** — TLS certificates issued and renewed automatically via ACME

The initial deploy uses [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to install NixOS onto any fresh Linux server. Subsequent deploys use `nixos-rebuild switch`.

### Prerequisites

- A fresh VPS/server (any Linux — nixos-anywhere will replace the OS). Must have `/dev/vda` as the primary disk.
- Nix with flakes enabled on your local machine
- SSH root access to the server
- A domain name

### 1. Configure the flake

Edit the three variables at the top of the `nixosConfigurations.goodtap` block in `flake.nix`:

```nix
domain    = "yourdomain.com";       # your domain
acmeEmail = "you@example.com";      # email for Let's Encrypt notifications
sshKey    = "ssh-ed25519 AAAA...";  # your public SSH key (cat ~/.ssh/id_ed25519.pub)
```

### 2. Point DNS to your server

Add an A record at your DNS provider:

| Type | Name | Value |
|------|------|-------|
| `A` | `yourdomain.com` | `<server IP>` |

Use a short TTL (e.g. 300s) so changes propagate quickly. Verify it has propagated before deploying:

```bash
dig yourdomain.com A +short
```

DNS must resolve to your server before nixos-anywhere runs, otherwise the Let's Encrypt certificate issuance will fail.

### 3. Get the deps hash

The `fetchMixDeps` derivation needs a content hash. Run a build once with the placeholder and copy the value from the error:

```bash
nix build .#packages.x86_64-linux.default 2>&1 | grep "got:"
```

Replace the `hash = "sha256-AAA..."` line in `flake.nix` with the printed value, then re-run to confirm it succeeds.

### 4. Generate a secret and deploy

Stage the secrets file locally, then pass it to nixos-anywhere via `--extra-files` so it is in place before the app first starts:

```bash
mkdir -p /tmp/goodtap-secrets/etc/goodtap
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" > /tmp/goodtap-secrets/etc/goodtap/secrets
chmod 600 /tmp/goodtap-secrets/etc/goodtap/secrets

nix run github:nix-community/nixos-anywhere -- \
  --build-on-remote \
  --extra-files /tmp/goodtap-secrets \
  --flake .#goodtap \
  root@<server-ip>

rm -rf /tmp/goodtap-secrets
```

> **macOS users:** `--build-on-remote` is required when deploying from a Mac, since Nix cannot natively build Linux derivations locally. nixos-anywhere boots a minimal NixOS environment on the server via kexec and runs the build there instead.

nixos-anywhere will partition the disk, install NixOS, copy the secrets file, and reboot. On first boot NixOS will:

1. Start PostgreSQL and create the `goodtap` database and user
2. Start nginx and obtain a Let's Encrypt TLS certificate
3. Run database migrations
4. Start the GoodTap service

Your app will be live at `https://yourdomain.com`.

### Subsequent deploys

```bash
nixos-rebuild switch --flake .#goodtap --target-host root@<server-ip>
```

Migrations run automatically on each restart.

### Useful commands on the server

```bash
# Check service status
systemctl status goodtap
systemctl status nginx

# View logs
journalctl -u goodtap -f
journalctl -u nginx -f

# Run a migration manually
/run/current-system/sw/bin/goodtap eval 'Goodtap.Release.migrate()'

# Connect to the database
psql -U goodtap goodtap
```
