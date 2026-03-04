#!/usr/bin/env bash
# Run this from the NixOS installer after nixos-install completes, before rebooting.
# Usage: bash diagnose-boot.sh

echo "====== lsblk ======"
lsblk -o NAME,PARTLABEL,PARTUUID,UUID,FSTYPE,SIZE,MOUNTPOINT

echo ""
echo "====== /dev/disk/by-partlabel/ ======"
ls -la /dev/disk/by-partlabel/ 2>/dev/null || echo "MISSING"

echo ""
echo "====== fstab (correct: from installed Nix store) ======"
find /mnt/nix/store -maxdepth 2 -name "etc-fstab" 2>/dev/null | while read f; do
  echo "--- $f ---"
  cat "$f"
done

echo ""
echo "====== /mnt/etc/static/fstab (what the booted system will use) ======"
STATIC=$(readlink -f /mnt/etc/static 2>/dev/null || echo "")
echo "static points to: $STATIC"
cat /mnt/etc/static/fstab 2>/dev/null || echo "NOT READABLE (symlink broken from outside chroot — expected)"
# Try resolving manually via /mnt
STATIC_MNT="/mnt${STATIC}"
echo "trying via /mnt: $STATIC_MNT/fstab"
cat "$STATIC_MNT/fstab" 2>/dev/null || echo "also not found via /mnt"

echo ""
echo "====== initrd path and modules ======"
INITRD_PATH=$(grep -o '/nix/store/[^ ]*/initrd' /mnt/boot/grub/grub.cfg | head -1)
echo "initrd path from grub.cfg: $INITRD_PATH"
INITRD="/mnt${INITRD_PATH}"
echo "looking at: $INITRD"

if [ -f "$INITRD" ]; then
  echo "initrd found, size: $(du -h "$INITRD" | cut -f1)"
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"

  # Try multiple decompression formats
  zcat "$INITRD" 2>/dev/null | cpio -idm 2>/dev/null || \
  xzcat "$INITRD" 2>/dev/null | cpio -idm 2>/dev/null || \
  (dd if="$INITRD" bs=512 skip=1 2>/dev/null | zcat | cpio -idm 2>/dev/null) || \
  echo "could not decompress initrd"

  echo ""
  echo "--- fstab inside initrd ---"
  cat etc/fstab 2>/dev/null || echo "no fstab in initrd"

  echo ""
  echo "--- virtio/scsi/ahci modules in initrd ---"
  find . -name "*.ko*" 2>/dev/null | grep -E "virtio|ahci|sd_mod|scsi|ata_" | sed 's|.*/||' | sort || echo "none found"

  echo ""
  echo "--- all .ko files in initrd ---"
  find . -name "*.ko*" 2>/dev/null | sed 's|.*/||' | sort

  cd /
  rm -rf "$TMPDIR"
else
  echo "initrd NOT FOUND at $INITRD"
fi

echo ""
echo "====== done ======"
