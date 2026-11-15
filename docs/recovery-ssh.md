# Boot recovery over emergency SSH

A short administrator guide, verified in a test VM on 2026-11-15.
This describes the draft's opt-in recovery SSH, not the behavior of a standard
legacy installation. It requires preconfigured recovery SSH/networking, an
authorized SSH key, and a recovery passphrase enrolled in LUKS.
This has not yet been deployed on production xs3.

## If TPM fails to unlock the disk

1. Connect to emergency SSH using your authorized key:

   ```sh
   ssh -p 2222 root@SERVER_IP
   ```

   For a non-default key:

   ```sh
   ssh -i /path/to/ssh-key -p 2222 root@SERVER_IP
   ```

   `SERVER_IP` is the early recovery network address. It is not necessarily
   the normal OS address; check the server's prepared configuration.

2. Run:

   ```sh
   cryptroot-unlock
   ```

3. Enter the **LUKS recovery passphrase** and press Enter. This is not an SSH
   password, an OS user password, or a TPM PIN. Characters are not displayed.
   Enter the passphrase at the prompt, not in a command or shell history.

4. Wait for the disk to unlock and boot to resume. Emergency SSH will close:
   this is normal, as Dropbear is stopped during the transition to the OS.
   A disconnection message alone does not prove that recovery succeeded.

5. Connect to the normal OS as your regular user on port 22:

   ```sh
   ssh USER@NORMAL_OS_IP
   ```

   If needed, check the root filesystem:

   ```sh
   findmnt -no SOURCE,FSTYPE /
   ```

   In our test this is `/dev/mapper/cryptroot-test ext4`, not the cleartext bootstrap.

## Troubleshooting

- A wrong passphrase leaves root locked. If the prompt returns, enter the
  correct passphrase; if the command exits, run `cryptroot-unlock` again.
  The number of attempts depends on crypttab.
- `Permission denied (publickey)` indicates an SSH key problem, not a LUKS
  passphrase problem. Use a key included in the recovery initramfs at build time.
- If port 2222 is unreachable, check the recovery IP, VLAN/network, and console/IPMI.
  Normal netplan is not available at this boot stage yet.
- **One-time recovery does not require `tpm2_clear`, `nvundefine`, resealing,
  or reinstallation.** This recovery path preserves TPM NV.
- If the cause of TPM failure is unknown, investigate it after recovery.
  Do not automatically accept the changed state as a new trusted baseline.

## Current test environment

- VM `tpm-km-recovery`, xs1 private NAT network.
- Emergency SSH: `192.168.122.227:2222`, user `root`.
- Normal OS during verification: `192.168.122.228:22`, user `ubuntu`.
- These are test DHCP addresses, **not production xs3 connection instructions**.
- Wrong passphrase -> root remains locked -> correct retry -> successful boot
  from encrypted root was verified live.
- Successful normal TPM unseal, an actual PCR mismatch with NV preservation,
  xs3 early VLAN networking, and a trusted boot chain still need verification.

Technical status and evidence: [Recovery SSH design](recovery-ssh-design.md).
