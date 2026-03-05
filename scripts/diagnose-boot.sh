#!/usr/bin/env bash
# Run this from the NixOS installer after nixos-install completes, before rebooting.

echo "====== fstab candidates in Nix store ======"
find /mnt/nix/store -maxdepth 3 -name "fstab" 2>/dev/null | while read f; do
  echo "--- $f ---"
  ls -la "$f"
  cat "$f" 2>/dev/null || echo "(symlink target missing)"
done

echo ""
echo "====== /mnt/etc/static symlink ======"
ls -la /mnt/etc/static 2>/dev/null || echo "missing"
readlink /mnt/etc/static 2>/dev/null || echo "not a symlink"

echo ""
echo "====== NixOS system init path ======"
INIT=$(grep -o '/nix/store/[^ ]*/init ' /mnt/boot/grub/grub.cfg | head -1 | tr -d ' ')
echo "init: $INIT"
SYSTEM_DIR=$(dirname "$INIT")
echo "system dir: $SYSTEM_DIR"
ls "/mnt${SYSTEM_DIR}/" 2>/dev/null || echo "not found"

echo ""
echo "====== etc symlink in system ======"
ls -la "/mnt${SYSTEM_DIR}/etc" 2>/dev/null || echo "not found"
ETC_TARGET=$(readlink "/mnt${SYSTEM_DIR}/etc" 2>/dev/null || echo "")
echo "etc -> $ETC_TARGET"
ls "/mnt${ETC_TARGET}/" 2>/dev/null || echo "not listable"
cat "/mnt${ETC_TARGET}/fstab" 2>/dev/null || echo "no fstab at /mnt${ETC_TARGET}/fstab"

echo ""
echo "====== initrd decompression ======"
INITRD_PATH=$(grep -o '/nix/store/[^ ]*/initrd' /mnt/boot/grub/grub.cfg | head -1)
INITRD="/mnt${INITRD_PATH}"
echo "initrd: $INITRD ($(du -h "$INITRD" 2>/dev/null | cut -f1))"

# Detect compression
MAGIC=$(dd if="$INITRD" bs=4 count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n')
echo "magic bytes: $MAGIC"

TMPDIR=$(mktemp -d)
cd "$TMPDIR"

if echo "$MAGIC" | grep -q "^28b52f"; then
  echo "format: zstd"
  zstd -d "$INITRD" -o initrd.cpio 2>/dev/null && cpio -idm < initrd.cpio 2>/dev/null
elif echo "$MAGIC" | grep -q "^1f8b"; then
  echo "format: gzip"
  zcat "$INITRD" | cpio -idm 2>/dev/null
elif echo "$MAGIC" | grep -q "^fd377a"; then
  echo "format: xz"
  xzcat "$INITRD" | cpio -idm 2>/dev/null
else
  echo "unknown format, trying zstd anyway"
  zstd -d "$INITRD" -o initrd.cpio 2>/dev/null && cpio -idm < initrd.cpio 2>/dev/null || echo "failed"
fi

echo ""
echo "--- fstab inside initrd ---"
cat etc/fstab 2>/dev/null || echo "no fstab in initrd"

echo ""
echo "--- modules.dep in initrd (shows available modules) ---"
find . -name "modules.dep" 2>/dev/null | head -3 | while read f; do
  echo "from $f:"
  grep -E "virtio|ahci|sd_mod|scsi" "$f" | head -20
done

echo ""
echo "--- virtio/scsi/ahci .ko files ---"
find . -name "*.ko*" 2>/dev/null | grep -E "virtio|ahci|sd_mod|scsi|ata_" | sed 's|.*/||' | sort

cd /
rm -rf "$TMPDIR"

echo ""
echo "====== done ======"
