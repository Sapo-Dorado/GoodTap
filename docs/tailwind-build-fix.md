# Tailwind CSS Build Fix Plan

## What We Know For Certain

1. **The tailwind binary is bun** — tailwind v4's standalone binary is a bun
   executable that uses `argv[0]` to detect whether it should run as `bun` or
   as the tailwind CLI. When the binary filename is `tailwindcss` it processes
   CSS. When named anything else (e.g. `tailwind-linux-x64`) it shows bun help
   and exits 0, producing no output.

2. **The mix tailwind task looks for the binary at `_build/tailwind-linux-x64`**
   — determined by `Tailwind.bin_path/0` which uses `tailwind-#{configured_target()}`.

3. **`TAILWIND_PATH` in config.exs is set via `System.get_env`** — this is
   evaluated at config load time during `mix compile`, which runs in `buildPhase`.
   Setting it as a derivation env var (our last attempt) should make it available
   then — but we haven't confirmed if this actually worked yet.

4. **The nixpkgs `tailwindcss` package IS also bun** — same binary, same argv[0]
   problem.

5. **esbuild works fine** — it's a normal binary with no argv[0] detection.

6. **Build output is empty CSS dir, non-empty JS dir** — esbuild succeeds,
   tailwind silently produces nothing.

## Root Cause

The mix tailwind task calls the binary at its configured path. That path is
either:
- `TAILWIND_PATH` env var (if set at compile time) → points to a file named `tailwindcss` ✓
- `_build/tailwind-linux-x64` (fallback) → named wrong, bun shows help ✗

Our attempts have been inconsistent because we haven't confirmed whether
`TAILWIND_PATH` is actually being picked up at compile time vs postBuild time.

## Diagnosis Steps (do these in order, stop when one confirms the issue)

### Step 1: Confirm current state — is TAILWIND_PATH being read?

After the next rebuild, check the build log for what binary path tailwind uses:

```bash
nix-store --read-log /nix/store/<latest-goodtap.drv> 2>&1 | grep -i "tailwind\|TAILWIND\|binary\|path\|bun"
```

If the log still shows bun help → `TAILWIND_PATH` env var is not being read
at the right time. Go to Fix A.

If the log shows tailwind actually running → the path is correct but something
else is wrong (input CSS not found, plugin error, etc.). Go to Fix B.

### Step 2: Confirm the binary actually works on the server

```bash
/nix/store/j1z332pgzdhzpxdamm3aqniqdi7k59rp-tailwindcss-4.1.12/bin/tailwindcss \
  --input /tmp/GoodTap/assets/css/app.css \
  --output /tmp/out.css 2>&1
cat /tmp/out.css | wc -c
```

If this produces output → the binary works, the issue is purely in how the
mix task invokes it. Go to Fix A.

If this fails with an error about plugins/imports → the CSS itself has issues
in the sandbox (missing vendor files, etc.). Go to Fix B.

---

## Fix A: Bypass the mix tailwind task entirely (most reliable)

Instead of using `mix assets.deploy` which calls the mix tailwind wrapper,
call the tailwind binary directly in `postBuild`. This bypasses all the
binary path detection logic:

```nix
postBuild = ''
  mkdir -p priv/static/assets/css priv/static/assets/js

  # Run tailwind directly — bypass mix task binary detection entirely
  ${tailwindcss}/bin/tailwindcss \
    --input=assets/css/app.css \
    --output=priv/static/assets/css/app.css \
    --minify

  # Run esbuild directly too for consistency
  ${pkgs.esbuild}/bin/esbuild assets/js/app.js \
    --bundle \
    --minify \
    --outfile=priv/static/assets/js/app.js \
    --target=es2017

  mix phx.digest
'';
```

**Why this works:** We use the Nix store path directly (which IS named
`tailwindcss`), so argv[0] is correct. No mix task binary detection involved.

**Risk:** We need to match the exact esbuild args that `mix esbuild goodtap
--minify` uses. Check `config/config.exs` for the configured args.

---

## Fix B: CSS input has errors in the Nix sandbox

If the tailwind binary runs but produces no output, the CSS input may be
failing silently. Common causes:

1. **Vendor plugin files not in src** — `@plugin "../vendor/heroicons"` etc.
   require `assets/vendor/*.js` to be present. Check they're in the git repo
   (not gitignored).

2. **`source(none)` with `@source` directives** — tailwind v4 with
   `source(none)` only scans explicitly listed `@source` paths. In the Nix
   sandbox the paths may not resolve correctly.

Diagnosis:
```bash
# On the server after disko, run tailwind with verbose output
/nix/store/.../tailwindcss \
  --input /tmp/GoodTap/assets/css/app.css \
  --output /tmp/out.css \
  2>&1
```

If it errors about missing files → add them to the repo or fix the paths.

---

## Fix C: Use node/npm based tailwind instead of standalone binary

If the standalone binary continues to be problematic, switch to the npm
package which doesn't have the argv[0] issue:

1. Add `package.json` to `assets/` with tailwind as a dependency
2. Use `pkgs.nodejs` in `nativeBuildInputs`
3. Run `npm install` in `preBuild`
4. Set `path` in tailwind config to `assets/node_modules/.bin/tailwindcss`

This is more complex but fully avoids the bun/argv[0] problem.

---

## Recommended Order

1. **Run Step 2 now** (test the binary directly on the server with the actual
   CSS file) — this takes 30 seconds and tells us if Fix A will work
2. **Implement Fix A** — it's the simplest and most direct approach
3. Only go to Fix B/C if Fix A fails

## After Fix is Confirmed Working

1. Remove the diagnostic `postBuild` verbosity
2. Update `docs/boot-diagnosis.md` with lessons learned
3. Update README deploy instructions
4. Save the correct `esbuild` args from `config/config.exs` into this doc
