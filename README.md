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

## Production deployment (NixOS)

The repo includes a Nix flake that builds the app and manages PostgreSQL as a persistent systemd service. Everything runs on a single NixOS host.

### Prerequisites

- A server running NixOS (or installed via [nixos-anywhere](https://github.com/nix-community/nixos-anywhere))
- Nix with flakes enabled on your local machine
- SSH access to the server

### 1. Generate the hardware configuration

On the server, run:

```bash
nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Add the file to the repo root (it is `.gitignore`-able if you prefer to keep it local).

### 2. Configure the flake

Edit `flake.nix` and update the `nixosConfigurations.goodtap` block:

```nix
services.goodtap = {
  enable = true;
  host = "yourdomain.com";  # <-- your actual hostname
  secretsFile = "/etc/goodtap/secrets";
};
```

### 3. Get the deps hash

The `fetchMixDeps` derivation needs a content hash. Run a build once with the placeholder hash and copy the value from the error output:

```bash
nix build .#packages.x86_64-linux.default 2>&1 | grep "got:"
```

Replace the `hash = "sha256-AAA..."` line in `flake.nix` with the printed hash, then re-run the build to confirm it succeeds.

### 4. Create the secrets file on the server

```bash
mkdir -p /etc/goodtap
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" > /etc/goodtap/secrets
chmod 600 /etc/goodtap/secrets
```

The file uses systemd `EnvironmentFile` format (`KEY=VALUE`, one per line). Add any other runtime secrets here (e.g. API keys).

### 5. Deploy

From the server itself:

```bash
nixos-rebuild switch --flake .#goodtap
```

Or remotely from your local machine:

```bash
nixos-rebuild switch --flake .#goodtap --target-host root@<server-ip>
```

On first deploy NixOS will:

1. Install and start PostgreSQL (data stored in `/var/lib/postgresql`)
2. Create the `goodtap` database and user
3. Build and install the Phoenix release
4. Run database migrations
5. Start the `goodtap` systemd service

Subsequent deploys follow the same command. Migrations run automatically on each restart.

### Optional: nginx reverse proxy

Uncomment and configure the nginx block in `flake.nix`:

```nix
services.nginx = {
  enable = true;
  virtualHosts."yourdomain.com" = {
    locations."/" = {
      proxyPass = "http://127.0.0.1:4000";
      proxyWebsockets = true;
    };
  };
};
```

### Useful commands on the server

```bash
# Check service status
systemctl status goodtap

# View logs
journalctl -u goodtap -f

# Run a one-off migration manually
/run/current-system/sw/bin/goodtap eval 'Goodtap.Release.migrate()'

# Connect to the database
psql -U goodtap goodtap
```
