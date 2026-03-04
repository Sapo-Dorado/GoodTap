# Boot Diagnosis: disk-main-root not found

## What We Know (Confirmed)

From our investigation on the installed system before reboot:

| Check | Result |
|-------|--------|
| Partition labels on disk | ✅ `disk-main-boot`, `disk-main-swap`, `disk-main-root` all present |
| GRUB in MBR | ✅ Present |
| grub.cfg | ✅ Correct, finds root by UUID `8c1a9d73-b13d-46ef-a59b-db99ff91cf6e` |
| fstab in Nix store | ✅ Correct, references `/dev/disk/by-partlabel/disk-main-root` |
| ext4 formatted on sda3 | ✅ Confirmed by `lsblk` |
| hardware-configuration.nix | ❌ Not generated (no nixos-generate-config was run) |

## Root Cause Hypothesis

The initrd boots fine and GRUB hands off correctly, but the initrd cannot
resolve `/dev/disk/by-partlabel/disk-main-root` because either:

1. **The disk driver isn't loaded in the initrd** — without `ahci`/`sd_mod`,
   the kernel can't see `/dev/sda` at all, so no partlabels appear in
   `/dev/disk/by-partlabel/`. This is the most likely cause since there is
   no `hardware-configuration.nix` to tell NixOS which drivers to include.

2. **udev doesn't run in time in the initrd** — the initrd gives up waiting
   before udev populates `/dev/disk/by-partlabel/`.

## Current State of Fixes Applied

- `boot.loader.grub.enable = true` with `efiSupport = false`
- `boot.initrd.availableKernelModules = [ "ahci" "sd_mod" "ata_piix" ]`
- No explicit `grub.device` (disko handles it)

These did not fix the issue. The `availableKernelModules` fix may not have
taken effect if the previously cached build was used.

---

## Plan: Three Parallel Approaches

Try these in order. Each is independent — if one works, stop.

---

### Approach A: Force UUID-based root mount (bypass partlabel entirely)

The fstab uses partlabel, but we know the UUID. Override it in `flake.nix`
to use UUID directly, which is more reliable and what GRUB already uses.

In `flake.nix`, add inside the inline NixOS module:

```nix
fileSystems."/" = lib.mkForce {
  device = "/dev/disk/by-uuid/605e0821-7344-4f12-9e70-ae82a49f0529";
  fsType = "ext4";
};
swapDevices = lib.mkForce [
  { device = "/dev/disk/by-uuid/531a4b9d-467d-49e1-b072-9c4e0ea1d37f"; }
];
```

UUIDs confirmed from our `lsblk` output:
- root (sda3): `605e0821-7344-4f12-9e70-ae82a49f0529`
- swap (sda2): `531a4b9d-467d-49e1-b072-9c4e0ea1d37f`

**Why this should work:** GRUB already finds root by this exact UUID. Using
UUID in fstab means the initrd doesn't need to resolve partlabels at all.

**Risk:** UUIDs are regenerated on each fresh install. If you wipe and
reinstall, UUIDs will change and the config will break. Use Approach B
instead for a permanent fix.

---

### Approach B: Generate hardware-configuration.nix properly

The real permanent fix is to run `nixos-generate-config` inside the
installed system so NixOS auto-detects the correct kernel modules and
filesystem UUIDs for this specific machine.

Steps:
1. Boot into kexec NixOS installer (interactive, not noninteractive)
2. Manually partition with disko or recreate partitions
3. Mount root at /mnt
4. Run `nixos-generate-config --root /mnt`
5. Copy the generated `hardware-configuration.nix` contents into `flake.nix`
   as a module (specifically the `boot.initrd.availableKernelModules` and
   `fileSystems` values)

The key values to extract from the generated file:
```nix
boot.initrd.availableKernelModules = [ ... ]; # will list correct drivers
boot.initrd.kernelModules = [ ... ];
fileSystems."/" = { device = "..."; fsType = "ext4"; };
```

---

### Approach C: Add all common Hetzner kernel modules

Rather than guessing, add the full set of modules Hetzner dedicated servers
commonly need. Replace the current `availableKernelModules` line with:

```nix
boot.initrd.availableKernelModules = [
  "ahci" "sd_mod" "ata_piix" "ata_generic"
  "xhci_pci" "ehci_pci" "uhci_hcd"
  "usb_storage" "usbcore"
  "e1000e" "r8169"           # common Hetzner NIC drivers (not needed for boot but safe)
];
boot.initrd.kernelModules = [ "dm_mod" ];
```

---

### Approach D: Inspect the actual initrd contents

If none of the above work, we need to see exactly what's in the initrd.
After a fresh install (before reboot), from the kexec environment:

```bash
# Find the initrd
ls /mnt/boot/

# Extract and inspect it
mkdir /tmp/initrd-inspect
cd /tmp/initrd-inspect
zcat /mnt/boot/initrd | cpio -idm 2>/dev/null || \
  (unlzma < /mnt/boot/initrd | cpio -idm)

# Check what modules are included
find . -name "*.ko" | grep -E "ahci|sd_mod|ata"

# Check the fstab inside the initrd
cat etc/fstab 2>/dev/null || echo "no fstab in initrd"

# Check init script for how root is found
cat init | grep -A5 -i "root\|mount"
```

This will definitively tell us whether the driver and fstab are present
inside the initrd image that gets loaded at boot.

---

## Recommended Order

1. **Do Approach A first** — quickest to test, uses known-good UUIDs
2. If A works but you want it clean, **do Approach B** to make it UUID-stable
3. If A fails, **do Approach D** to see exactly what's in the initrd before
   trying more config changes blindly
