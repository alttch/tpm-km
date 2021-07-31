# tpm-km

Yet another pack of scripts for TPM2+luks and similar tasks.

## Why

tpm-km can:

* verify PCR state before sealing key and abort if some PCRs are empty
* protect key with additional PIN (AES256)
* ask for PINs and passwords in a nice dialog windows :)
* split secret key in chunks and protect them with different PCR policies

![pin dialog](https://github.com/alttch/tpm-km/blob/master/images/dialog.png?raw=true)

## Setup

* Install *dialog*, *tpm2-tools* (make sure you have 3.x or above) and *figlet*
  (optional)

```shell
    sudo apt -y install dialog tpm2-tools figlet
```

* Clear TPM2 module and take ownership

```shell
    sudo tpm2_clear
    # for tpm2 tools below v4:
    # sudo tpm2_takeownership -c
```

* If you have graphics splash screen - remove it, otherwise you'll not see
  PIN/password dialog windows: make sure there's no *splash* in
  */etc/default/grub*, if exists - remove it and run *update_grub* to apply new
  configuration.

* Install tpm-km

```shell
    sudo ./install.sh
```

Install script will copy:

* /usr/local/sbin/generate-secret-key.sh - key generator
* /usr/local/sbin/seal-tpm.sh - TPM sealing script
* /sbin/getsecret.sh - TPM reader script
* /etc/initramfs-tools/hooks/tpm-hook - initramfs-ready TPM hook
* /usr/local/etc/tpm_km - configuration file

* It's also strongly recommended to configure UEFI Secure Boot and use grub >=
  2.04 (or systemd-boot), as grub prior 2.04 doesn't work with TPM and your
  system can be owned if someone put own kernel or initrd.

## Generate key and seal it to TPM

* Generate secret key. By default, 128-bytes alpha-numeric key is generated (as
  tpm-km is written in bash and doesn't like binary data) and put in
  /secret.key file with 000 permissions.

```shell
    sudo /usr/local/sbin/generate-secret-key.sh
```

* Add this key to luks:

```shell
    sudo cryptsetup luksAddKey /dev/my-encrypted-drive /secret.key
```

* Put TPM reader script to your crypttab:

```
    <container>  UUID=<FS_UUID>   none    luks,discard,initramfs,keyscript=/sbin/getsecret.sh
```

* Remake initial ramdisk:

```shell
    sudo update-initramfs -u -v
```

It's also recommended to backup your previous initrd\*.img files to return them
if something go wrong.

* **Reboot** your system with new ramdisk. TPM reader script will report an
  error, that's fine. Enter your usual luks password, when prompted.

* Seal the key to TPM:

```shell
    sudo /usr/local/sbin/seal-tpm.sh
```

You'll be prompted for PIN, twice.

* Reboot again and enter your PIN instead of password. If it works - congrats,
  you have TPM2+luks with PIN protection.

You must re-seal key into TPM every time when something your system is changed
(depending which PCRs you use).

If you want to store sealing PIN, put it to file */usr/local/etc/tpm_sealpin*
(don't forget to set 600 permissions on it).

## FAQ

### What PIN is used for?

PIN is used to add additional protection to your system. Without PIN attacker
can not boot your system to login prompt, so he can not use any local or
network exploits.

When booted, there are 3 attempts to enter PIN, after the 3rd attempt, the key
is deleted from TPM.

WARNING: using PIN before v1.2 may be insecure.

### Can I boot my system without PIN?

If you've forgot your PIN, just press Cancel at PIN prompt dialog. The key will
be deleted from TPM and the script fall back to password prompt. After booting,
you may re-seal keys back to TPM.

### Can I disable PIN protection?

This is insecure, but yes, of course you can. Put a default PIN into
configuration file and that's it. Don't forget to re-create initrd as well.

### Should PIN be only numeric?

In tpm-km, PIN is just called "PIN", because most of encrypted disk mangers use
numeric PINs. But no - it can be alpha-numeric and include special symbols.
It's up to you.

### What can be configured?

PIN, key file location, PCR sets, TPM addresses, dialog args (e.g. remove
--insecure to enter PINs and passwords without the "stars")

Everything else can be configured inside scripts code :)

Note: after any change in /usr/local/etc/tpm_km you must rebuild initial
ramdisk.

### Does it work with TPM1.2?

No

### Where can I get grub >= 2.04?

Grub 2.04 is already included into RHEL 8.0, Fedora 30, Ubuntu 19.10 and maybe
some other Linux distros.

### What if I don't use grub?

If you don't use grub (e.g. use systemd-boot instead), remove PCRs 8 and 9 from
/usr/local/etc/tpm_km (unless they're filled by your loader).

### Why secret key is being split?

By default, tpm-km splits key in 2 chunks. TPM 2.0 specification doesn't
allow TPM policy with more than 8 PCRs at once. With 2 chunks you can use
almost all filled PCRs and make system protection much stronger. Just make sure
PCRs 0,2,4,7 (and 9 for grub) are present in both sets.

### Compatibility

For tpm2_tools below 4.0 (e.g. Ubuntu 19.10 and earlier), use release 1.0. For
tpm2 tools v4 use version 1.1+ or master branch.

### No tpm device during boot

If initramfs fails with "/dev/tpm0 not found" error, make sure TPM modules are
included into initial ram disk. Add the following to
/etc/initramfs-tools/modules:

```
tpm
tpm_crb
tpm_tis
tpm_tis_core
rng_core
ccp
```
