# Recovery SSH experiment (work in progress)

Dedicated workshop VM: tpm-km-recovery, NAT 192.168.122.227.
Original tpm-km-lab is shut down, preserved for PCR15 testing.
Ubuntu 26.04, Secure Boot and separate vTPM2, 2 GiB RAM.
Bootstrap disk vda retains cleartext bootstrap and separate boot/EFI partitions.
The 20 GiB vdb now contains a real LUKS encrypted root. Recovery and pivot
were live-verified 2026-11-15; see evidence below. This is not production readiness.

Implementation:
- Optional --with-recovery-ssh, mutually exclusive with PCR15 root measurement.
- Require real LUKS-backed root, no silently assumed encrypted root.
- Package Dropbear via stock dropbear-initramfs build hook.
- At build time move stock init-premount/dropbear outside automatic script dirs.
- TPM keyscript failure starts this saved script once; stock init-bottom cleanup retained.
- TPM failure must preserve NV; no automatic nvundefine.
- Need ensure cryptroot-unlock is compatible with the custom keyscript:
  inspect cryptroot askpass/cryptroot-unlock protocol before implementation.
- Early networking uses explicit DHCP/static configuration; arbitrary netplan
  (bridge/bond/VLAN) is not supported until its renderer is bundled and tested.
- Root authorized_keys copied at build time, password SSH disabled.
- Keep SSH host key distinct from live OS.
- Recovery secret entered interactively, never stored in initramfs.
- Initrd authentication/measurement required; test old-initrd and cmdline changes.

Tests pending:
1. Encrypted-root normal boot via TPM, no recovery listener/network startup.
2. TPM policy mismatch starts network and SSH without clearing NV.
3. Wrong SSH key denied; authorized recovery unlock resumes boot.
4. Dropbear and early-network processes cleaned on pivot.
5. Recovery failure does not boot cleartext bootstrap or leak disk key.

PCR15 branch pending:
New list includes /lib,/bin,/sbin,/lib64 links and libexec/local libraries.
Previous list produced repeatable PCR15; new list hasn't had repeatability
or sealed-secret tamper tests completed. Full trust-closure review remains
(/usr/share scripts, /opt, /var/spool/cron, cloud-init state, user startup).


## Live recovery evidence — 2026-11-15

Dedicated disposable VM only, production xs3 untouched.

- Failed TPM read (test NV index absent) starts Dropbear on TCP2222.
- Non-authorized host keys denied; dedicated lab-key accepted.
- Found stale deployed helper without console redirection. Dropbear inherited
  the keyscript stdout pipe, keeping cryptsetup waiting for EOF. The draft's
  existing `</dev/null >/dev/console 2>&1` fix was installed into the encrypted
  guest root, then update-initramfs rebuilt its actual /boot on vda13.
- Original fixture keyfile had a trailing newline. Interactive askpass does
  not preserve it. Added a separate newline-free test recovery passphrase slot;
  original key/slot preserved. No real credentials or key bytes in this doc.
- After reboot, unmodified stock cryptroot-unlock accepted the test passphrase:
  `cryptsetup: cryptroot-test set up successfully`, exit0.
- QEMU guest agent and normal SSH independently confirmed actual root
  `/dev/mapper/cryptroot-test` ext4, vdb crypto_LUKS, vda1 not root/mounted.
- multi-user.target active; Dropbear absent and TCP2222 listener absent, SSH22 up.
- Initrd DHCP address .227, OS DHCP address .228: do not assume one address.
- Cleartext bootstrap and boot artifacts remain attached: this is a recovery
  functionality test, not proof against alternate boot or initrd substitution.

Still pending: successful TPM-unseal normal boot with no recovery listener;
actual PCR-policy mismatch with preservation of existing test NV contents;
VLAN/static early network suitable for xs3; combined
PCR15/recovery integration (currently mutually exclusive); boot-chain security.

Repeat boot: wrong passphrase returned exit1, `/dev/mapper/cryptroot-test`
remained absent and recovery SSH stayed available. A subsequent correct
passphrase via stock cryptroot-unlock returned exit0 and boot resumed.
