#!/usr/bin/env bash
# Run this from the NixOS installer after disko has partitioned the disk
# and nixos-install has completed, but BEFORE rebooting.
# Usage: bash diagnose-boot.sh

set -euo pipefail

echo "====== lsblk ======"
lsblk -o NAME,PARTLABEL,PARTUUID,UUID,FSTYPE,SIZE,MOUNTPOINT

echo ""
echo "====== /dev/disk/by-partlabel/ ======"
ls -la /dev/disk/by-partlabel/ 2>/dev/null || echo "MISSING"

echo ""
echo "====== /dev/disk/by-uuid/ ======"
ls -la /dev/disk/by-uuid/ 2>/dev/null || echo "MISSING"

echo ""
echo "====== fstab (via symlink chain) ======"
FSTAB=$(readlink -f /mnt/etc/fstab 2>/dev/null || echo "")
if [ -n "$FSTAB" ] && [ -f "$FSTAB" ]; then
  cat "$FSTAB"
else
  # Try finding it in the store
  FSTAB_STORE=$(find /mnt/nix/store -maxdepth 3 -name "etc-fstab" 2>/dev/null | head -1)
  if [ -n "$FSTAB_STORE" ]; then
    cat "$FSTAB_STORE"
  else
    echo "NOT FOUND"
  fi
fi

echo ""
echo "====== grub.cfg ======"
cat /mnt/boot/grub/grub.cfg 2>/dev/null || echo "NOT FOUND"

echo ""
echo "====== initrd kernel modules ======"
INITRD=$(ls /mnt/boot/initrd 2>/dev/null || ls /mnt/boot/initrd-* 2>/dev/null | head -1 || echo "")
if [ -n "$INITRD" ]; then
  echo "initrd found at: $INITRD"
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  # Try multiple decompression formats
  (zcat "$INITRD" | cpio -idm 2>/dev/null) || \
  (xzcat "$INITRD" | cpio -idm 2>/dev/null) || \
  (lz4cat "$INITRD" | cpio -idm 2>/dev/null) || \
  echo "could not decompress initrd"

  echo "--- kernel modules in initrd ---"
  find . -name "*.ko*" | grep -E "ahci|virtio|sd_mod|scsi|ata" || echo "none of the expected modules found"

  echo "--- all kernel modules in initrd ---"
  find . -name "*.ko*" | sed 's|.*/||' | sort

  echo "--- fstab inside initrd ---"
  cat etc/fstab 2>/dev/null || echo "no fstab in initrd"

  echo "--- init script root mount section ---"
  grep -A5 -i "partlabel\|by-uuid\|root=" init 2>/dev/null || echo "not found in init"

  cd /
  rm -rf "$TMPDIR"
else
  echo "initrd NOT FOUND at /mnt/boot/"
  ls /mnt/boot/
fi

echo ""
echo "====== NixOS system path ======"
ls /mnt/nix/var/nix/profiles/ 2>/dev/null || echo "NOT FOUND"

echo ""
echo "====== done ======"
