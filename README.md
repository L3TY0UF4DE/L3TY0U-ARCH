# L3TY0U-ARCH

`L3TY0U-ARCH` is an interactive Arch Linux install script for building a custom system from the Arch ISO.

It asks what you want installed, formats the selected drive, installs Arch, creates your user, installs your chosen desktop/apps, and enables the matching services.

## Status

This is ready for careful VM testing.

Do not run it on your main machine or an important drive until it has been tested on disposable virtual machines.

## What It Can Do

- Ask which disk to erase and install Arch onto
- Require an exact destructive confirmation before wiping the disk
- Create a UEFI/GPT install layout
- Choose root filesystem: `ext4`, `btrfs`, or `xfs`
- Create Btrfs subvolumes when Btrfs is selected
- Configure optional swap
- Set hostname, timezone, keyboard layout, root password, and user password
- Optionally enable multilib
- Optionally install CPU microcode
- Optionally detect and install basic GPU drivers
- Ask for desktop environment/window manager
- Ask for display manager
- Ask for web browsers
- Ask for terminal emulators
- Ask for file managers
- Ask for shell
- Ask for editors
- Ask for AUR helper
- Install optional package groups like audio, Bluetooth, printing, gaming, dev tools, fonts, media, laptop tools, and security tools

## Current Limits

- UEFI only
- No BIOS/legacy boot support yet
- No LUKS/encryption yet
- No dual-boot support
- No manual partition reuse
- No separate `/home` partition option yet
- Assumes `/mnt` as the install target
- GPU detection is basic
- AUR installs require working network access in the new system

## How To Test

Boot the official Arch ISO in a virtual machine using UEFI mode.

Clone or copy this project into the live environment, then run:

```bash
chmod +x arch-custom-install.sh
sudo ./arch-custom-install.sh --dry-run
```

If the dry run looks right, test on a disposable virtual disk:

```bash
sudo ./arch-custom-install.sh
```

The script will show a summary before doing anything destructive. Before formatting, it will also require you to type:

```text
ERASE /dev/yourdisk
```

## Non-Formatting Mode

To use the script only for package/app setup on an already installed Arch system:

```bash
sudo ./arch-custom-install.sh --no-format --user yourusername
```

## Customizing Packages

Most choices live near the top of `arch-custom-install.sh` in editable arrays:

- `DESKTOP_ENVIRONMENTS`
- `DISPLAY_MANAGERS`
- `WEB_BROWSERS`
- `TERMINALS`
- `FILE_MANAGERS`
- `AUR_HELPERS`
- `SHELLS`
- `EDITOR_OPTIONS`
- `OPTIONAL_GROUPS`

Add or remove package names there to make the installer match your setup.

## Credits

Inspired by ideas from:

- [Linutil](https://github.com/ChrisTitusTech/linutil)
- [ArchTitus](https://github.com/christitustech/archtitus)

This script is its own implementation.
