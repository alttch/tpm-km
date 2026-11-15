#!/bin/sh
set -eu
with_pcr15=0
with_recovery=0
file_list=etc/pcr15-files.list
while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-recovery-ssh) with_recovery=1; shift;;
    --with-pcr15) with_pcr15=1; shift;;
    --pcr15-files) [ "$#" -ge 2 ] || exit 2; file_list=$2; shift 2;;
    *) echo "Usage: $0 [--with-pcr15] [--pcr15-files FILE]" >&2; exit 2;;
  esac
done
[ "$with_pcr15:$with_recovery" != 1:1 ] || exit 2
[ "$(id -u)" = 0 ] || { echo "Run as root" >&2; exit 1; }
[ -r "$file_list" ] || exit 2
install -d /usr/local/sbin /usr/local/etc /etc/initramfs-tools/hooks
install -m 755 sbin/generate-secret-key.sh sbin/seal-tpm.sh /usr/local/sbin/
install -m 755 sbin/getsecret.sh /sbin/
install -m 755 etc/tpm-hook /etc/initramfs-tools/hooks/
[ -f /usr/local/etc/tpm_km ] || install -m 600 etc/tpm_km /usr/local/etc/
if [ "$with_pcr15" = 1 ]; then
  command -v python3 >/dev/null
  command -v tpm2_pcrextend >/dev/null
  install -d /usr/local/lib/tpm-km /etc/tpm-km /etc/initramfs-tools/scripts/local-bottom
  install -m 755 sbin/tpm-km-manifest.py /usr/local/lib/tpm-km/manifest.py
  install -m 755 sbin/tpm-km-measure-rootfs /usr/local/sbin/
  install -m 755 etc/pcr15-hook /etc/initramfs-tools/hooks/
  install -m 755 etc/pcr15-local-bottom /etc/initramfs-tools/scripts/local-bottom/
  # Preserve administrator customizations on reinstall.
  [ -f /etc/tpm-km/pcr15-files.list ] || install -m 644 "$file_list" /etc/tpm-km/pcr15-files.list
  sed -i '/^PCR15_ENABLED=/d' /usr/local/etc/tpm_km
  echo 'PCR15_ENABLED=1' >> /usr/local/etc/tpm_km
fi
if [ "$with_recovery" = 1 ]; then
  test -f /usr/share/initramfs-tools/hooks/dropbear
  test -s /root/.ssh/authorized_keys
  install -d /etc/dropbear/initramfs
  install -m 600 /root/.ssh/authorized_keys /etc/dropbear/initramfs/authorized_keys
  install -m 755 sbin/tpm-km-recovery-ssh /usr/local/sbin/
  install -m 755 etc/recovery-ssh-hook /etc/initramfs-tools/hooks/
  sed -i '/^RECOVERY_SSH_ENABLED=/d' /usr/local/etc/tpm_km
  echo 'RECOVERY_SSH_ENABLED=1' >> /usr/local/etc/tpm_km
fi
echo 'Installed. Configure, rebuild initramfs, boot measurement, then seal. No NV changed.'
