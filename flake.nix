{
  description = "GoodTap Phoenix LiveView application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      makePackage = system:
        let
          pkgs = pkgsFor system;
          beamPkgs = pkgs.beam.packages.erlang_27;
          elixir = beamPkgs.elixir_1_18;

          mixFodDeps = beamPkgs.fetchMixDeps {
            pname = "goodtap-deps";
            version = "0.1.0";
            src = ./.;
            # Run `nix build .#packages.x86_64-linux.default` once with this
            # placeholder; Nix will print the correct hash in the error output.
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };
        in
        beamPkgs.mixRelease {
          pname = "goodtap";
          version = "0.1.0";
          src = ./.;
          inherit elixir mixFodDeps;

          nativeBuildInputs = [ pkgs.git ];

          # The mix esbuild/tailwind packages respect these env vars instead of
          # downloading binaries, letting us use Nix-provided versions.
          postBuild = ''
            export TAILWIND_PATH=${pkgs.tailwindcss}/bin/tailwindcss
            export ESBUILD_PATH=${pkgs.esbuild}/bin/esbuild
            mix do assets.deploy, phx.digest
          '';
        };

    in
    {
      packages = forAllSystems (system: {
        default = makePackage system;
      });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          beamPkgs = pkgs.beam.packages.erlang_27;
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              beamPkgs.elixir_1_18
              beamPkgs.erlang
              pkgs.postgresql_17
              pkgs.nodejs_22
              pkgs.tailwindcss
              pkgs.esbuild
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.inotify-tools ];
          };
        }
      );

      # -----------------------------------------------------------------------
      # NixOS module — import this in any NixOS configuration
      # -----------------------------------------------------------------------
      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.goodtap;
          goodtap = self.packages.${pkgs.system}.default;
        in
        {
          options.services.goodtap = {
            enable = mkEnableOption "GoodTap Phoenix application";

            port = mkOption {
              type = types.port;
              default = 4000;
              description = "HTTP port the Phoenix server binds to.";
            };

            host = mkOption {
              type = types.str;
              default = "localhost";
              description = "Public hostname used for URL generation (PHX_HOST).";
            };

            secretsFile = mkOption {
              type = types.path;
              description = ''
                Path to a file containing environment variables (systemd EnvironmentFile format).
                Must contain at minimum:
                  SECRET_KEY_BASE=<64-byte hex string>
                Generate with: nix run nixpkgs#elixir -- -e 'IO.puts :crypto.strong_rand_bytes(64) |> Base.encode16()'
                Or locally:    mix phx.gen.secret
              '';
            };

            stateDir = mkOption {
              type = types.path;
              default = "/var/lib/goodtap";
              readOnly = true;
              description = "Runtime state directory (tmp files, uploads, etc.).";
            };
          };

          config = mkIf cfg.enable {
            # PostgreSQL — data is stored in /var/lib/postgresql and persists across reboots
            services.postgresql = {
              enable = true;
              ensureDatabases = [ "goodtap" ];
              ensureUsers = [{
                name = "goodtap";
                ensureDBOwnership = true;
              }];
              # Allow the goodtap OS user to connect via localhost without a password.
              # Only processes running as the goodtap system user can trigger these
              # rules (TCP to 127.0.0.1), so this is safe for a single-host setup.
              authentication = lib.mkAfter ''
                host goodtap goodtap 127.0.0.1/32 trust
                host goodtap goodtap ::1/128      trust
              '';
            };

            users.users.goodtap = {
              isSystemUser = true;
              group = "goodtap";
              home = cfg.stateDir;
              createHome = true;
            };
            users.groups.goodtap = { };

            systemd.services.goodtap = {
              description = "GoodTap Phoenix Application";
              after = [ "network.target" "postgresql.service" ];
              requires = [ "postgresql.service" ];
              wantedBy = [ "multi-user.target" ];

              environment = {
                PHX_SERVER = "true";
                PHX_HOST = cfg.host;
                PORT = toString cfg.port;
                # No password needed — PostgreSQL trusts the goodtap OS user on localhost
                DATABASE_URL = "ecto://goodtap@localhost/goodtap";
                RELEASE_TMP = "${cfg.stateDir}/tmp";
                HOME = cfg.stateDir;
              };

              serviceConfig = {
                Type = "exec";
                User = "goodtap";
                Group = "goodtap";
                WorkingDirectory = cfg.stateDir;
                # Secrets (SECRET_KEY_BASE, etc.) are loaded from this file
                EnvironmentFile = cfg.secretsFile;
                # Run DB migrations before starting the server
                ExecStartPre = "${goodtap}/bin/goodtap eval 'Goodtap.Release.migrate()'";
                ExecStart = "${goodtap}/bin/goodtap start";
                Restart = "on-failure";
                RestartSec = "5s";
                # Basic hardening
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ReadWritePaths = [ cfg.stateDir ];
              };
            };
          };
        };

      # -----------------------------------------------------------------------
      # Example NixOS host configuration
      #
      # Deployment workflow:
      #   1. Boot the server into NixOS minimal installer (or existing NixOS)
      #   2. Generate hardware config and save it here:
      #        nixos-generate-config --show-hardware-config > hardware-configuration.nix
      #   3. Edit the options below (host, etc.)
      #   4. Create the secrets file on the server:
      #        mkdir -p /etc/goodtap
      #        echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" > /etc/goodtap/secrets
      #        chmod 600 /etc/goodtap/secrets
      #   5. Deploy (from your local machine or from the server):
      #        nixos-rebuild switch --flake .#goodtap [--target-host root@<server-ip>]
      # -----------------------------------------------------------------------
      nixosConfigurations.goodtap = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          [
            self.nixosModules.default

            ({ pkgs, lib, ... }: {
              services.goodtap = {
                enable = true;
                host = "yourdomain.com"; # <-- change this
                # Create on the server: see step 4 above
                secretsFile = "/etc/goodtap/secrets";
              };

              # Optional: nginx reverse proxy
              # services.nginx = {
              #   enable = true;
              #   virtualHosts."yourdomain.com" = {
              #     locations."/" = {
              #       proxyPass = "http://127.0.0.1:4000";
              #       proxyWebsockets = true;
              #     };
              #   };
              # };

              networking.hostName = "goodtap";
              networking.firewall.allowedTCPPorts = [ 80 443 4000 ];

              # Enable SSH so you can reach the box after deploy
              services.openssh.enable = true;

              system.stateVersion = "24.11";
            })
          ]
          # hardware-configuration.nix is machine-specific — generate it on
          # your server with: nixos-generate-config --show-hardware-config
          # then save it as ./hardware-configuration.nix in this repo.
          ++ nixpkgs.lib.optional
            (builtins.pathExists ./hardware-configuration.nix)
            ./hardware-configuration.nix;
      };
    };
}
