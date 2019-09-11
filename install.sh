#!/bin/sh

cp -vf sbin/generate-secret-key.sh /usr/local/sbin/ || exit 1
cp -vf sbin/seal-tpm.sh /usr/local/sbin/ || exit 1
cp -vf sbin/getsecret.sh /sbin/ || exit 1

cp -vf etc/tpm-hook /etc/initramfs-tools/hooks/ || exit 2

if [ ! -f /usr/local/etc/tpm_km ]; then
  cp -v etc/tpm_km /usr/local/etc/ || exit 3
fi

echo 'Installed. Now configure LUKS and exec "update-initramfs -u -v -k all"'
