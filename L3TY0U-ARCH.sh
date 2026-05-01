#!/usr/bin/env bash
set -Eeuo pipefail

# Interactive Arch Linux installer.
# Intended for the official Arch ISO or an installed Arch system.

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-./arch-custom-install.log}"
PACMAN_FLAGS=("--needed" "--noconfirm")
TARGET_MOUNT="${TARGET_MOUNT:-/mnt}"
TARGET_DISK=""
EFI_PARTITION=""
ROOT_PARTITION=""
SWAP_PARTITION=""
FILESYSTEM="ext4"
SWAP_SIZE_GIB="0"
HOSTNAME="archlinux"
TIMEZONE="${TIMEZONE:-America/Toronto}"
KEYMAP="us"
MOUNT_OPTIONS="noatime,compress=zstd,ssd,commit=120"
ENABLE_MULTILIB=0
INSTALL_MICROCODE=1
INSTALL_GPU_DRIVERS=1
ROOT_PASSWORD=""
USER_PASSWORD=""
FORMAT_DISK=1

DESKTOP_ENVIRONMENTS=(
  "none|No desktop environment|"
  "gnome|GNOME|gnome gnome-tweaks"
  "kde|KDE Plasma|plasma kde-applications"
  "xfce|Xfce|xfce4 xfce4-goodies"
  "cinnamon|Cinnamon|cinnamon"
  "mate|MATE|mate mate-extra"
  "lxqt|LXQt|lxqt"
  "i3|i3 window manager|i3-wm i3status i3lock dmenu"
  "sway|Sway Wayland compositor|sway swaybg swayidle swaylock waybar wofi"
  "hyprland|Hyprland Wayland compositor|hyprland waybar rofi-wayland"
)

DISPLAY_MANAGERS=(
  "none|No display manager|"
  "gdm|GDM|gdm"
  "sddm|SDDM|sddm"
  "lightdm|LightDM|lightdm lightdm-gtk-greeter"
  "ly|Ly terminal display manager|ly"
)

WEB_BROWSERS=(
  "firefox|Firefox|firefox"
  "chromium|Chromium|chromium"
  "brave|Brave Browser AUR|brave-bin"
  "vivaldi|Vivaldi|vivaldi"
  "librewolf|LibreWolf AUR|librewolf-bin"
  "zen|Zen Browser AUR|zen-browser-bin"
)

TERMINALS=(
  "alacritty|Alacritty|alacritty"
  "kitty|Kitty|kitty"
  "wezterm|WezTerm|wezterm"
  "gnome-terminal|GNOME Terminal|gnome-terminal"
  "konsole|Konsole|konsole"
  "xfce4-terminal|Xfce Terminal|xfce4-terminal"
  "foot|Foot Wayland terminal|foot"
)

FILE_MANAGERS=(
  "nautilus|Files/Nautilus|nautilus"
  "dolphin|Dolphin|dolphin"
  "thunar|Thunar|thunar thunar-archive-plugin tumbler"
  "nemo|Nemo|nemo"
  "pcmanfm-qt|PCManFM-Qt|pcmanfm-qt"
  "ranger|Ranger terminal file manager|ranger"
  "yazi|Yazi terminal file manager|yazi"
)

AUR_HELPERS=(
  "none|No AUR helper|"
  "yay|yay|yay"
  "paru|paru|paru"
)

SHELLS=(
  "bash|Bash|bash"
  "zsh|Zsh|zsh zsh-completions"
  "fish|Fish|fish"
)

EDITOR_OPTIONS=(
  "nano|Nano|nano"
  "vim|Vim|vim"
  "neovim|Neovim|neovim"
  "emacs|Emacs|emacs"
  "vscode|Visual Studio Code OSS|code"
  "vscodium|VSCodium AUR|vscodium-bin"
)

OPTIONAL_GROUPS=(
  "base|Base quality-of-life tools|base-devel git curl wget unzip zip p7zip man-db man-pages texinfo openssh rsync reflector"
  "audio|Audio stack|pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber pavucontrol"
  "bluetooth|Bluetooth|bluez bluez-utils blueman"
  "printing|Printing/scanning|cups system-config-printer sane simple-scan"
  "network|Network tools|networkmanager network-manager-applet firewalld ufw"
  "graphics|Graphics tools|gimp inkscape blender krita"
  "media|Media apps/codecs|vlc mpv ffmpeg obs-studio"
  "gaming|Gaming|steam lutris gamemode mangohud wine winetricks"
  "dev|Developer tools|docker docker-compose nodejs npm python python-pip go rustup"
  "laptop|Laptop/power tools|tlp powertop acpi brightnessctl"
  "fonts|Fonts|noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu"
  "security|Security tools|gnupg keepassxc seahorse"
)

SERVICE_MAP=(
  "NetworkManager:network"
  "bluetooth:bluetooth"
  "cups:printing"
  "firewalld:network"
  "tlp:laptop"
  "docker:dev"
)

SELECTED_PACKAGES=()
SELECTED_AUR_PACKAGES=()
SELECTED_GROUP_KEYS=()
DISPLAY_MANAGER_SERVICE=""
CHOSEN_AUR_HELPER=""
CHOSEN_SHELL_KEY=""
TARGET_USER="${SUDO_USER:-}"
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: ./$SCRIPT_NAME [options]

Options:
  --dry-run       Print the commands that would run without installing.
  --user USER     User account for AUR builds and shell changes.
  --log FILE      Write an install log to FILE. Default: $LOG_FILE
  --no-format     Skip disk formatting and install packages on the running system.
  -h, --help      Show this help.

Run this from the official Arch ISO for a fresh install.
WARNING: the default flow asks which disk to erase, partitions it, and formats it.
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

run() {
  log "+ $*"
  if (( DRY_RUN == 0 )); then
    "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

run_allow_fail() {
  log "+ $*"
  if (( DRY_RUN == 0 )); then
    "$@" 2>&1 | tee -a "$LOG_FILE" || true
  fi
}

as_user() {
  local user="$1"
  shift
  log "+ sudo -u $user $*"
  if (( DRY_RUN == 0 )); then
    sudo -u "$user" "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

run_in_target() {
  log "+ arch-chroot $TARGET_MOUNT $*"
  if (( DRY_RUN == 0 )); then
    arch-chroot "$TARGET_MOUNT" "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

run_in_target_as_user() {
  local user="$1"
  shift
  log "+ arch-chroot $TARGET_MOUNT sudo -u $user $*"
  if (( DRY_RUN == 0 )); then
    arch-chroot "$TARGET_MOUNT" sudo -u "$user" "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

partition_path() {
  local disk="$1"
  local number="$2"
  if [[ "$disk" =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$disk" "$number"
  else
    printf '%s%s\n' "$disk" "$number"
  fi
}

split_packages() {
  local package_list="$1"
  [[ -z "$package_list" ]] && return 0
  # shellcheck disable=SC2206
  local packages=( $package_list )
  SELECTED_PACKAGES+=("${packages[@]}")
}

split_aur_packages() {
  local package_list="$1"
  [[ -z "$package_list" ]] && return 0
  # shellcheck disable=SC2206
  local packages=( $package_list )
  SELECTED_AUR_PACKAGES+=("${packages[@]}")
}

entry_key() {
  cut -d'|' -f1 <<<"$1"
}

entry_label() {
  cut -d'|' -f2 <<<"$1"
}

entry_packages() {
  cut -d'|' -f3- <<<"$1"
}

is_aur_package() {
  [[ "$1" == *" AUR" || "$1" == *"AUR"* ]]
}

prompt_single() {
  local title="$1"
  shift
  local entries=("$@")
  local choice

  printf '\n%s\n' "$title" >&2
  for i in "${!entries[@]}"; do
    printf '  %2d) %s\n' "$((i + 1))" "$(entry_label "${entries[$i]}")" >&2
  done

  while true; do
    read -r -p "Choose one [1-${#entries[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#entries[@]} )); then
      printf '%s\n' "${entries[$((choice - 1))]}"
      return 0
    fi
    printf 'Please enter a number from 1 to %d.\n' "${#entries[@]}" >&2
  done
}

prompt_multi() {
  local title="$1"
  shift
  local entries=("$@")
  local answer

  printf '\n%s\n' "$title" >&2
  for i in "${!entries[@]}"; do
    printf '  %2d) %s\n' "$((i + 1))" "$(entry_label "${entries[$i]}")" >&2
  done
  printf 'Enter numbers separated by spaces, "all", or press Enter for none.\n' >&2

  while true; do
    read -r -p "Choices: " answer
    [[ -z "$answer" ]] && return 0

    if [[ "$answer" == "all" ]]; then
      for entry in "${entries[@]}"; do
        printf '%s\n' "$entry"
      done
      return 0
    fi

    local valid=1
    # shellcheck disable=SC2206
    local choices=( $answer )
    for choice in "${choices[@]}"; do
      if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#entries[@]} )); then
        valid=0
        break
      fi
    done

    if (( valid == 1 )); then
      for choice in "${choices[@]}"; do
        printf '%s\n' "${entries[$((choice - 1))]}"
      done
      return 0
    fi

    printf 'Use numbers from 1 to %d, separated by spaces.\n' "${#entries[@]}" >&2
  done
}

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local answer suffix
  [[ "$default" == "y" ]] && suffix="[Y/n]" || suffix="[y/N]"
  read -r -p "$prompt $suffix " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

prompt_text() {
  local prompt="$1"
  local default="${2:-}"
  local answer
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer
    printf '%s\n' "${answer:-$default}"
  else
    read -r -p "$prompt: " answer
    printf '%s\n' "$answer"
  fi
}

prompt_password() {
  local prompt="$1"
  local first second
  while true; do
    read -r -s -p "$prompt: " first
    printf '\n' >&2
    read -r -s -p "Confirm $prompt: " second
    printf '\n' >&2
    if [[ -n "$first" && "$first" == "$second" ]]; then
      printf '%s\n' "$first"
      return 0
    fi
    printf 'Passwords did not match, or were empty. Try again.\n' >&2
  done
}

choose_filesystem() {
  local entry
  entry="$(prompt_single "Root filesystem" \
    "ext4|ext4|ext4" \
    "btrfs|Btrfs|btrfs" \
    "xfs|XFS|xfs")"
  FILESYSTEM="$(entry_key "$entry")"
}

choose_mount_options() {
  [[ "$FILESYSTEM" == "btrfs" ]] || return 0

  if confirm "Is the target disk an SSD/NVMe drive?" "y"; then
    MOUNT_OPTIONS="noatime,compress=zstd,ssd,commit=120"
  else
    MOUNT_OPTIONS="noatime,compress=zstd,commit=120"
  fi
}

choose_swap() {
  local value
  while true; do
    value="$(prompt_text "Swap partition size in GiB, or 0 for no swap" "0")"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      SWAP_SIZE_GIB="$value"
      return 0
    fi
    printf 'Please enter a whole number, like 0, 4, 8, or 16.\n' >&2
  done
}

choose_disk() {
  local disks=()
  local line choice

  printf '\nAvailable install disks\n' >&2
  lsblk -dpo NAME,SIZE,MODEL,TYPE | sed -n '1p;/disk$/p' >&2

  while IFS= read -r line; do
    disks+=("$line|$line|$line")
  done < <(lsblk -dpno NAME,TYPE | awk '$2 == "disk" {print $1}')

  ((${#disks[@]} > 0)) || die "No installable disks were found."
  choice="$(prompt_single "Which disk should be erased and used for Arch?" "${disks[@]}")"
  TARGET_DISK="$(entry_key "$choice")"
}

collect_disk_choices() {
  choose_disk
  choose_filesystem
  choose_mount_options
  choose_swap
}

confirm_disk_wipe() {
  local typed
  printf '\nWARNING: %s will be completely erased.\n' "$TARGET_DISK" >&2
  lsblk "$TARGET_DISK" >&2 || true
  printf '\nType exactly ERASE %s to continue.\n' "$TARGET_DISK" >&2
  read -r -p "> " typed
  [[ "$typed" == "ERASE $TARGET_DISK" ]] || die "Disk wipe confirmation failed."
}

format_and_mount_disk() {
  local part_num=1
  confirm_disk_wipe

  EFI_PARTITION="$(partition_path "$TARGET_DISK" "$part_num")"
  part_num=$((part_num + 1))

  if (( SWAP_SIZE_GIB > 0 )); then
    SWAP_PARTITION="$(partition_path "$TARGET_DISK" "$part_num")"
    part_num=$((part_num + 1))
  fi

  ROOT_PARTITION="$(partition_path "$TARGET_DISK" "$part_num")"

  run swapoff -a
  run_allow_fail umount -R "$TARGET_MOUNT"
  run wipefs -af "$TARGET_DISK"
  run sgdisk --zap-all "$TARGET_DISK"
  run sgdisk -n 1:0:+1GiB -t 1:ef00 -c 1:EFI "$TARGET_DISK"

  if (( SWAP_SIZE_GIB > 0 )); then
    run sgdisk -n 2:0:+"${SWAP_SIZE_GIB}"GiB -t 2:8200 -c 2:swap "$TARGET_DISK"
    run sgdisk -n 3:0:0 -t 3:8300 -c 3:root "$TARGET_DISK"
  else
    run sgdisk -n 2:0:0 -t 2:8300 -c 2:root "$TARGET_DISK"
  fi

  run partprobe "$TARGET_DISK"
  run mkfs.fat -F32 "$EFI_PARTITION"

  case "$FILESYSTEM" in
    ext4)
      run mkfs.ext4 -F "$ROOT_PARTITION"
      ;;
    btrfs)
      run mkfs.btrfs -f "$ROOT_PARTITION"
      ;;
    xfs)
      run mkfs.xfs -f "$ROOT_PARTITION"
      ;;
    *) die "Unsupported filesystem: $FILESYSTEM" ;;
  esac

  if [[ -n "$SWAP_PARTITION" ]]; then
    run mkswap "$SWAP_PARTITION"
    run swapon "$SWAP_PARTITION"
  fi

  run mkdir -p "$TARGET_MOUNT"
  if [[ "$FILESYSTEM" == "btrfs" ]]; then
    run mount "$ROOT_PARTITION" "$TARGET_MOUNT"
    run btrfs subvolume create "$TARGET_MOUNT/@"
    run btrfs subvolume create "$TARGET_MOUNT/@home"
    run btrfs subvolume create "$TARGET_MOUNT/@var"
    run btrfs subvolume create "$TARGET_MOUNT/@tmp"
    run btrfs subvolume create "$TARGET_MOUNT/@.snapshots"
    run umount "$TARGET_MOUNT"
    run mount -o "$MOUNT_OPTIONS,subvol=@" "$ROOT_PARTITION" "$TARGET_MOUNT"
    run mkdir -p "$TARGET_MOUNT"/{boot,home,var,tmp,.snapshots}
    run mount -o "$MOUNT_OPTIONS,subvol=@home" "$ROOT_PARTITION" "$TARGET_MOUNT/home"
    run mount -o "$MOUNT_OPTIONS,subvol=@var" "$ROOT_PARTITION" "$TARGET_MOUNT/var"
    run mount -o "$MOUNT_OPTIONS,subvol=@tmp" "$ROOT_PARTITION" "$TARGET_MOUNT/tmp"
    run mount -o "$MOUNT_OPTIONS,subvol=@.snapshots" "$ROOT_PARTITION" "$TARGET_MOUNT/.snapshots"
  else
    run mount "$ROOT_PARTITION" "$TARGET_MOUNT"
    run mkdir -p "$TARGET_MOUNT/boot"
  fi
  run mount "$EFI_PARTITION" "$TARGET_MOUNT/boot"
}

collect_base_system_choices() {
  HOSTNAME="$(prompt_text "Hostname" "$HOSTNAME")"
  TIMEZONE="$(prompt_text "Timezone" "$TIMEZONE")"
  KEYMAP="$(prompt_text "Keyboard layout" "$KEYMAP")"

  if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(prompt_text "Main username" "archuser")"
  fi

  if confirm "Enable multilib for Steam, Wine, and 32-bit packages?" "y"; then
    ENABLE_MULTILIB=1
  fi

  if confirm "Install CPU microcode automatically?" "y"; then
    INSTALL_MICROCODE=1
  else
    INSTALL_MICROCODE=0
  fi

  if confirm "Detect and install basic GPU drivers?" "y"; then
    INSTALL_GPU_DRIVERS=1
  else
    INSTALL_GPU_DRIVERS=0
  fi

  ROOT_PASSWORD="$(prompt_password "root password")"
  USER_PASSWORD="$(prompt_password "$TARGET_USER password")"
}

install_base_system() {
  local base_packages=(
    base linux linux-firmware
    sudo vim nano
    networkmanager
    grub efibootmgr
  )

  case "$FILESYSTEM" in
    btrfs) base_packages+=(btrfs-progs) ;;
    xfs) base_packages+=(xfsprogs) ;;
  esac

  if (( INSTALL_MICROCODE == 1 )); then
    if grep -q GenuineIntel /proc/cpuinfo; then
      base_packages+=(intel-ucode)
    elif grep -q AuthenticAMD /proc/cpuinfo; then
      base_packages+=(amd-ucode)
    fi
  fi

  run pacstrap -K "$TARGET_MOUNT" "${base_packages[@]}"
  run genfstab -U "$TARGET_MOUNT"
  if (( DRY_RUN == 0 )); then
    genfstab -U "$TARGET_MOUNT" >> "$TARGET_MOUNT/etc/fstab"
  fi
}

configure_base_system() {
  run_in_target ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  run_in_target hwclock --systohc
  run_in_target sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  run_in_target locale-gen
  run_in_target bash -lc "printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf"
  run_in_target bash -lc "printf 'KEYMAP=%s\n' '$KEYMAP' > /etc/vconsole.conf"
  run_in_target bash -lc "printf '%s\n' '$HOSTNAME' > /etc/hostname"
  run_in_target systemctl enable NetworkManager

  if (( ENABLE_MULTILIB == 1 )); then
    run_in_target sed -i '/^\#\[multilib\]/,/^\#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
    run_in_target pacman -Sy --noconfirm
  fi

  if (( DRY_RUN == 0 )); then
    printf 'root:%s\n' "$ROOT_PASSWORD" | arch-chroot "$TARGET_MOUNT" chpasswd
    arch-chroot "$TARGET_MOUNT" useradd -m -G wheel -s /bin/bash "$TARGET_USER"
    printf '%s:%s\n' "$TARGET_USER" "$USER_PASSWORD" | arch-chroot "$TARGET_MOUNT" chpasswd
  else
    log "+ set root password"
    log "+ create user $TARGET_USER"
    log "+ set $TARGET_USER password"
  fi

  run_in_target sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
  run_in_target grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
  run_in_target grub-mkconfig -o /boot/grub/grub.cfg
}

add_detected_hardware_packages() {
  (( INSTALL_GPU_DRIVERS == 1 )) || return 0
  command -v lspci >/dev/null 2>&1 || return 0

  local gpu_info
  gpu_info="$(lspci)"

  if grep -Eq "NVIDIA|GeForce" <<<"$gpu_info"; then
    SELECTED_PACKAGES+=(nvidia nvidia-utils nvidia-settings)
  elif grep -Eq "VGA|3D|Display" <<<"$gpu_info" && grep -Eq "Radeon|AMD|ATI" <<<"$gpu_info"; then
    SELECTED_PACKAGES+=(mesa vulkan-radeon libva-mesa-driver mesa-vdpau)
    (( ENABLE_MULTILIB == 1 )) && SELECTED_PACKAGES+=(lib32-mesa lib32-vulkan-radeon)
  elif grep -Eq "VGA|3D|Display" <<<"$gpu_info" && grep -Eq "Intel Corporation|UHD Graphics|Iris" <<<"$gpu_info"; then
    SELECTED_PACKAGES+=(mesa vulkan-intel intel-media-driver libva-utils)
    (( ENABLE_MULTILIB == 1 )) && SELECTED_PACKAGES+=(lib32-mesa lib32-vulkan-intel)
  fi
}

contains_group() {
  local group="$1"
  local selected
  for selected in "${SELECTED_GROUP_KEYS[@]}"; do
    [[ "$selected" == "$group" ]] && return 0
  done
  return 1
}

dedupe_array() {
  awk '!seen[$0]++'
}

pacman_install() {
  local packages
  packages="$(printf '%s\n' "${SELECTED_PACKAGES[@]}" | sed '/^$/d' | dedupe_array | tr '\n' ' ')"
  [[ -z "$packages" ]] && return 0
  # shellcheck disable=SC2086
  if (( FORMAT_DISK == 1 )); then
    run_in_target pacman -S "${PACMAN_FLAGS[@]}" $packages
  else
    run pacman -S "${PACMAN_FLAGS[@]}" $packages
  fi
}

aur_install() {
  local packages
  packages="$(printf '%s\n' "${SELECTED_AUR_PACKAGES[@]}" | sed '/^$/d' | dedupe_array | tr '\n' ' ')"
  [[ -z "$packages" ]] && return 0

  [[ -n "$CHOSEN_AUR_HELPER" && "$CHOSEN_AUR_HELPER" != "none" ]] || die "AUR packages were selected but no AUR helper was chosen."
  [[ -n "$TARGET_USER" ]] || die "Set --user USER so AUR packages can be built without root."
  if (( FORMAT_DISK == 1 )); then
    arch-chroot "$TARGET_MOUNT" id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' does not exist in the new system."
  else
    id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' does not exist."
  fi

  install_aur_helper "$CHOSEN_AUR_HELPER"
  # shellcheck disable=SC2086
  if (( FORMAT_DISK == 1 )); then
    run_in_target_as_user "$TARGET_USER" "$CHOSEN_AUR_HELPER" -S "${PACMAN_FLAGS[@]}" $packages
  else
    as_user "$TARGET_USER" "$CHOSEN_AUR_HELPER" -S "${PACMAN_FLAGS[@]}" $packages
  fi
}

install_aur_helper() {
  local helper="$1"
  [[ "$helper" == "none" || -z "$helper" ]] && return 0
  if (( FORMAT_DISK == 1 )); then
    arch-chroot "$TARGET_MOUNT" bash -lc "command -v '$helper'" >/dev/null 2>&1 && return 0
  else
    command -v "$helper" >/dev/null 2>&1 && return 0
  fi

  [[ -n "$TARGET_USER" ]] || die "Set --user USER so $helper can be built without root."
  if (( FORMAT_DISK == 1 )); then
    arch-chroot "$TARGET_MOUNT" id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' does not exist in the new system."
  else
    id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' does not exist."
  fi

  if (( FORMAT_DISK == 1 )); then
    run_in_target pacman -S "${PACMAN_FLAGS[@]}" base-devel git sudo
    run_in_target_as_user "$TARGET_USER" bash -lc "rm -rf /tmp/$helper && git clone https://aur.archlinux.org/$helper.git /tmp/$helper && cd /tmp/$helper && makepkg -si --noconfirm"
  else
    run pacman -S "${PACMAN_FLAGS[@]}" base-devel git
    as_user "$TARGET_USER" bash -lc "rm -rf /tmp/$helper && git clone https://aur.archlinux.org/$helper.git /tmp/$helper && cd /tmp/$helper && makepkg -si --noconfirm"
  fi
}

enable_services() {
  local item service group

  if [[ -n "$DISPLAY_MANAGER_SERVICE" ]]; then
    if (( FORMAT_DISK == 1 )); then
      run_in_target systemctl enable "$DISPLAY_MANAGER_SERVICE"
    else
      run systemctl enable "$DISPLAY_MANAGER_SERVICE"
    fi
  fi

  for item in "${SERVICE_MAP[@]}"; do
    service="${item%%:*}"
    group="${item##*:}"
    if contains_group "$group"; then
      if (( FORMAT_DISK == 1 )); then
        run_in_target systemctl enable "$service"
      else
        run systemctl enable "$service"
      fi
    fi
  done
}

set_login_shell() {
  local shell_key="$1"
  local shell_path=""
  [[ -z "$TARGET_USER" ]] && return 0

  case "$shell_key" in
    bash) shell_path="/bin/bash" ;;
    zsh) shell_path="/bin/zsh" ;;
    fish) shell_path="/usr/bin/fish" ;;
    *) return 0 ;;
  esac

  if confirm "Set $TARGET_USER's login shell to $shell_path?" "n"; then
    if (( FORMAT_DISK == 1 )); then
      run_in_target chsh -s "$shell_path" "$TARGET_USER"
    else
      run chsh -s "$shell_path" "$TARGET_USER"
    fi
  fi
}

collect_choices() {
  local entry key label packages

  entry="$(prompt_single "Desktop environment/window manager" "${DESKTOP_ENVIRONMENTS[@]}")"
  packages="$(entry_packages "$entry")"
  split_packages "$packages"

  entry="$(prompt_single "Display manager" "${DISPLAY_MANAGERS[@]}")"
  key="$(entry_key "$entry")"
  packages="$(entry_packages "$entry")"
  split_packages "$packages"
  [[ "$key" != "none" ]] && DISPLAY_MANAGER_SERVICE="$key"

  entry="$(prompt_single "AUR helper" "${AUR_HELPERS[@]}")"
  CHOSEN_AUR_HELPER="$(entry_key "$entry")"

  while IFS= read -r entry; do
    label="$(entry_label "$entry")"
    packages="$(entry_packages "$entry")"
    if is_aur_package "$label"; then
      split_aur_packages "$packages"
    else
      split_packages "$packages"
    fi
  done < <(prompt_multi "Web browsers" "${WEB_BROWSERS[@]}")

  while IFS= read -r entry; do
    split_packages "$(entry_packages "$entry")"
  done < <(prompt_multi "Terminals" "${TERMINALS[@]}")

  while IFS= read -r entry; do
    split_packages "$(entry_packages "$entry")"
  done < <(prompt_multi "File managers" "${FILE_MANAGERS[@]}")

  entry="$(prompt_single "Default shell to install" "${SHELLS[@]}")"
  key="$(entry_key "$entry")"
  CHOSEN_SHELL_KEY="$key"
  split_packages "$(entry_packages "$entry")"

  while IFS= read -r entry; do
    label="$(entry_label "$entry")"
    packages="$(entry_packages "$entry")"
    if is_aur_package "$label"; then
      split_aur_packages "$packages"
    else
      split_packages "$packages"
    fi
  done < <(prompt_multi "Editors" "${EDITOR_OPTIONS[@]}")

  while IFS= read -r entry; do
    SELECTED_GROUP_KEYS+=("$(entry_key "$entry")")
    split_packages "$(entry_packages "$entry")"
  done < <(prompt_multi "Optional package groups" "${OPTIONAL_GROUPS[@]}")
}

show_summary() {
  printf '\nInstall summary\n'
  if (( FORMAT_DISK == 1 )); then
    printf '  Fresh install target:\n'
    printf '    - Disk to erase: %s\n' "$TARGET_DISK"
    printf '    - EFI partition: 1 GiB FAT32 mounted at /boot\n'
    printf '    - Root filesystem: %s\n' "$FILESYSTEM"
    [[ "$FILESYSTEM" == "btrfs" ]] && printf '    - Btrfs mount options: %s\n' "$MOUNT_OPTIONS"
    printf '    - Swap: %s GiB\n' "$SWAP_SIZE_GIB"
    printf '    - Hostname: %s\n' "$HOSTNAME"
    printf '    - Timezone: %s\n' "$TIMEZONE"
    printf '    - Keyboard layout: %s\n' "$KEYMAP"
    printf '    - Main user: %s\n' "$TARGET_USER"
    printf '    - Multilib: %s\n' "$([[ "$ENABLE_MULTILIB" == 1 ]] && printf enabled || printf disabled)"
    printf '    - CPU microcode: %s\n' "$([[ "$INSTALL_MICROCODE" == 1 ]] && printf enabled || printf disabled)"
    printf '    - GPU driver detection: %s\n' "$([[ "$INSTALL_GPU_DRIVERS" == 1 ]] && printf enabled || printf disabled)"
  fi

  printf '  Pacman packages:\n'
  printf '%s\n' "${SELECTED_PACKAGES[@]}" | sed '/^$/d' | dedupe_array | sed 's/^/    - /'

  if ((${#SELECTED_AUR_PACKAGES[@]} > 0)); then
    printf '  AUR packages via %s:\n' "$CHOSEN_AUR_HELPER"
    printf '%s\n' "${SELECTED_AUR_PACKAGES[@]}" | sed '/^$/d' | dedupe_array | sed 's/^/    - /'
  fi

  if [[ -n "$DISPLAY_MANAGER_SERVICE" ]]; then
    printf '  Display manager service: %s\n' "$DISPLAY_MANAGER_SERVICE"
  fi

  if ((${#SELECTED_GROUP_KEYS[@]} > 0)); then
    printf '  Optional groups:\n'
    printf '%s\n' "${SELECTED_GROUP_KEYS[@]}" | sed 's/^/    - /'
  fi
  printf '\n'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --user)
        TARGET_USER="${2:-}"
        [[ -n "$TARGET_USER" ]] || die "--user requires a username."
        shift 2
        ;;
      --log)
        LOG_FILE="${2:-}"
        [[ -n "$LOG_FILE" ]] || die "--log requires a file path."
        shift 2
        ;;
      --no-format)
        FORMAT_DISK=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

preflight() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root, for example: sudo ./$SCRIPT_NAME --user yourname"
  command -v pacman >/dev/null 2>&1 || die "This script is intended for Arch Linux systems with pacman."

  if (( FORMAT_DISK == 1 )); then
    [[ -d /sys/firmware/efi/efivars ]] || die "This installer currently supports UEFI installs only. Boot the Arch ISO in UEFI mode."
    for command_name in lsblk sgdisk wipefs mkfs.fat partprobe pacstrap genfstab arch-chroot; do
      command -v "$command_name" >/dev/null 2>&1 || die "Missing required command: $command_name"
    done
  fi

  if [[ -z "$TARGET_USER" ]]; then
    if (( FORMAT_DISK == 1 )); then
      TARGET_USER="archuser"
    else
      printf 'No target user was detected. AUR installs and shell changes need one.\n'
      read -r -p "Target username, or press Enter to skip AUR/user changes: " TARGET_USER
    fi
  fi
}

main() {
  parse_args "$@"
  : > "$LOG_FILE"
  preflight

  log "Starting $SCRIPT_NAME"

  if (( FORMAT_DISK == 1 )); then
    collect_base_system_choices
    collect_disk_choices
  fi

  collect_choices
  add_detected_hardware_packages
  show_summary | tee -a "$LOG_FILE"

  if ! confirm "Proceed with installation?" "n"; then
    log "Cancelled."
    exit 0
  fi

  if (( FORMAT_DISK == 1 )); then
    format_and_mount_disk
    install_base_system
    configure_base_system
  fi

  pacman_install
  aur_install
  enable_services
  set_login_shell "$CHOSEN_SHELL_KEY"

  log "Done. Reboot when you are ready."
}

main "$@"
