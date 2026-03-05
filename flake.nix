{
  description = "GoodTap Phoenix LiveView application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, }:
    let
      supportedSystems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
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
            hash = "sha256-hTmfuLL0eTPtDQt7GdusTHxgTeGk8O4/cO26TsfuKuA=";
          };

          # heroicons SVGs are downloaded by `mix deps.get` from GitHub at version 2.2.0.
          # We fetch them as a fixed-output derivation so they're available in the sandbox.
          heroiconsSrc = pkgs.fetchzip {
            url = "https://github.com/tailwindlabs/heroicons/archive/refs/tags/v2.2.0.zip";
            hash = "sha256-Jcxr1fSbmXO9bZKeg39Z/zVN0YJp17TX3LH5Us4lsZU=";
          };

        in beamPkgs.mixRelease {
          pname = "goodtap";
          version = "0.1.3"; # keep in sync with mix.exs
          src = ./.;
          inherit elixir mixFodDeps;

          nativeBuildInputs = [ pkgs.git pkgs.tailwindcss_4 pkgs.esbuild ];

          # TAILWIND_PATH and ESBUILD_PATH are read by config/config.exs at
          # compile time via System.get_env, so they must be set as derivation
          # environment variables, not in postBuild.
          TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
          ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";

          # heroicons.js plugin reads SVGs from deps/heroicons/optimized at build time.
          # The SVGs are fetched separately since mixFodDeps only has compiled beam files.
          preBuild = ''
            mkdir -p deps/heroicons
            ln -sf ${heroiconsSrc}/optimized deps/heroicons/optimized
          '';

          postBuild = ''
            mkdir -p priv/static/assets/css priv/static/assets/js
            mix do assets.deploy, phx.digest
          '';
        };

    in {
      packages = forAllSystems (system: { default = makePackage system; });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          beamPkgs = pkgs.beam.packages.erlang_27;
        in {
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
        });

      # -----------------------------------------------------------------------
      # NixOS module — import this in any NixOS configuration
      # -----------------------------------------------------------------------
      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.goodtap;
          goodtap = self.packages.${pkgs.system}.default;
        in {
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
              description =
                "Public hostname used for URL generation (PHX_HOST).";
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
              description =
                "Runtime state directory (tmp files, uploads, etc.).";
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
                # Ensure RELEASE_TMP exists before the release tries to write the cookie
                ExecStartPre = [
                  "${pkgs.coreutils}/bin/mkdir -p ${cfg.stateDir}/tmp"
                  "${goodtap}/bin/goodtap eval 'Goodtap.Release.migrate()'"
                ];
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
      #   1. Edit domain, acmeEmail, and sshKey below           <-- you must do this
      #   2. Create the secrets file on the server after deploy:
      #        ssh root@<server-ip> "mkdir -p /etc/goodtap && \
      #          echo SECRET_KEY_BASE=$(openssl rand -hex 64) > /etc/goodtap/secrets && \
      #          chmod 600 /etc/goodtap/secrets"
      #   3. Point your domain's DNS A record to the server IP
      #   4. Run nixos-anywhere from your local machine:
      #        nix run github:nix-community/nixos-anywhere -- --flake .#goodtap root@<server-ip>
      #   5. Future updates (after initial install):
      #        nixos-rebuild switch --flake .#goodtap --target-host root@<server-ip>
      # -----------------------------------------------------------------------
      nixosConfigurations.goodtap = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          self.nixosModules.default
          ./hardware/hetzner-hardware-configuration.nix

          ({ pkgs, lib, ... }:
            let
              domain = "goodtap.in";
              acmeEmail = "sapodorado@proton.me";
              sshKey =
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKW8DZZYK2k5aOg8f/dfscXLG9bOLLzTU/6h8uWP5Rrw";
            in {

              # ---- Disk layout (disko — used by nixos-anywhere to partition the disk) ----
              disko.devices.disk.main = {
                device = "/dev/sda";
                type = "disk";
                content = {
                  type = "gpt";
                  partitions = {
                    boot = {
                      size = "1M";
                      type = "EF02"; # BIOS boot partition (required for GRUB on GPT)
                    };
                    swap = {
                      size = "2G";
                      content.type = "swap";
                    };
                    root = {
                      size = "100%";
                      content = {
                        type = "filesystem";
                        format = "ext4";
                        mountpoint = "/";
                      };
                    };
                  };
                };
              };

              # ---- Bootloader ----
              # disko automatically configures mirroredBoots based on the disk layout;
              # setting grub.device(s) manually would duplicate the entry and fail.
              boot.loader.grub.enable = true;
              boot.loader.grub.efiSupport = false;


              # ---- SSH access ----
              users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

              # ---- Application ----
              services.goodtap = {
                enable = true;
                host = domain;
                secretsFile = "/etc/goodtap/secrets";
              };

              # ---- nginx reverse proxy (terminates SSL, forwards to Phoenix :4000) ----
              services.nginx = {
                enable = true;
                recommendedProxySettings = true;
                recommendedTlsSettings = true;
                recommendedGzipSettings = true;
                recommendedOptimisation = true;

                virtualHosts.${domain} = {
                  enableACME = true; # automatic Let's Encrypt cert
                  forceSSL = true; # redirect HTTP → HTTPS

                  locations."/" = {
                    proxyPass = "http://127.0.0.1:4000";
                    proxyWebsockets = true; # required for LiveView
                  };
                };
              };

              # ---- Let's Encrypt (cert renewal handled automatically by systemd timer) ----
              security.acme = {
                acceptTerms = true;
                defaults.email = acmeEmail;
              };

              networking.hostName = "goodtap";
              # Port 4000 not exposed — nginx is the only public entry point
              networking.firewall.allowedTCPPorts = [ 22 80 443 ];

              services.openssh.enable = true;

              system.stateVersion = "24.11";
            })
        ];
      };
    };
}
