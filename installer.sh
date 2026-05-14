#!/usr/bin/env bash
# ============================================================
#  C-OS Installer  v1.4  --  KDE Plasma Edition
#  Arch Linux based C-OS installation script
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'
DIM='\033[2m'; NC='\033[0m'

# ============================================================
#  BANNER
# ============================================================
show_banner() {
    clear
    echo -e "${CYAN}"
    echo '                                      ________________________________________________'
    echo '                                     /                                                \'
    echo '                                     |         ____           _____    ______         |'
    echo '                                     |        / ___|         /  _  \  /  ___/         |'
    echo '                                     |       | |      _____  | | | |  | |___          |'
    echo '                                     |       | |     |_____| | | | |  \___  \         |'
    echo '                                     |       | |___          | |_| |   ___)  |        |'
    echo '                                     |        \____|         \_____/ /_____ /         |'
    echo '                                     |                                                |'
    echo '                                     |                    Welcome!                    |'
    echo '                                     =================================================='
    echo -e "${NC}"
    echo -e "${DIM}                         Arch Linux based C-OS Installation Wizard -- KDE Plasma Edition${NC}"
    echo
}

# ============================================================
#  HELPERS
# ============================================================
info()    { echo -e "  ${CYAN}[INFO]${NC}    $*"; }
success() { echo -e "  ${GREEN}[OK]${NC}      $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}    $*"; }
error()   { echo -e "  ${RED}[ERROR]${NC}   $*"; exit 1; }
step()    {
    echo
    echo -e "${BOLD}${BLUE}  ======================================================"
    echo -e "  $*"
    echo -e "  ======================================================${NC}"
    echo
}
confirm() {
    echo -ne "  ${YELLOW}[INPUT]${NC}   $1 [y/N]: "
    read -r ans; [[ "$ans" =~ ^[Yy]$ ]]
}

num_select() {
    local -n _res=$1
    local title="$2"
    local prompt="$3"
    shift 3
    local items=("$@")
    local count=${#items[@]}

    echo -e "  ${BOLD}${title}${NC}"
    echo
    for i in "${!items[@]}"; do
        local num=$(( i + 1 ))
        if [[ $i -eq 0 ]]; then
            echo -e "  ${CYAN}${BOLD}  $num)${NC}  ${items[$i]}  ${DIM}[default]${NC}"
        else
            echo -e "  ${DIM}  $num)${NC}  ${items[$i]}"
        fi
    done
    echo
    while true; do
        echo -ne "  ${YELLOW}[INPUT]${NC}   ${prompt} [1-${count}] (default: 1): "
        read -r choice
        [[ -z "$choice" ]] && choice=1
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 )) && (( choice <= count )); then
            _res="${items[$(( choice - 1 ))]}"
            break
        else
            warn "Invalid selection. Enter a number between 1 and ${count}."
        fi
    done
}

# ============================================================
#  PRE-CHECK
# ============================================================
pre_check() {
    step "System Check"
    [[ $EUID -ne 0 ]] && error "This script must be run as root."
    ping -c1 -W3 archlinux.org &>/dev/null || error "No internet connection."
    success "Internet connection available."
    [[ -d /sys/firmware/efi ]] && BOOT_MODE="UEFI" || BOOT_MODE="BIOS"
    success "Boot mode detected: ${BOLD}${BOOT_MODE}${NC}"
}

# ============================================================
#  DISK SELECTION
# ============================================================
select_disk() {
    step "Disk Selection"
    mapfile -t DISKS < <(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk"{print "/dev/"$1" ("$2")"}')
    [[ ${#DISKS[@]} -eq 0 ]] && error "No disks found."
    local chosen
    num_select chosen "Select installation disk:" "Enter disk number" "${DISKS[@]}"
    TARGET_DISK=$(echo "$chosen" | awk '{print $1}')
    echo
    success "Selected disk: ${BOLD}${TARGET_DISK}${NC}"
    echo
    warn "${RED}${BOLD}WARNING:${NC} All data on ${TARGET_DISK} will be permanently erased."
    confirm "Continue?" || { info "Installation cancelled."; exit 0; }
}

# ============================================================
#  KEYBOARD LAYOUT
# ============================================================
select_keymap() {
    step "Keyboard Layout"
    local KEYMAP_LABELS=(
        "trq      Turkish Q"
        "trf      Turkish F"
        "us       English (US)"
        "uk       English (UK)"
        "de       German"
        "fr       French"
        "es       Spanish"
        "it       Italian"
        "ru       Russian"
        "pl       Polish"
        "colemak  Colemak"
        "dvorak   Dvorak"
    )
    local chosen
    num_select chosen "Select keyboard layout:" "Enter layout number" "${KEYMAP_LABELS[@]}"
    KEYMAP=$(echo "$chosen" | awk '{print $1}')
    loadkeys "$KEYMAP" &>/dev/null || true
    echo
    success "Keyboard layout set: ${BOLD}${KEYMAP}${NC}"
}

# ============================================================
#  ROOT PASSWORD
# ============================================================
set_root_password() {
    step "Root Password"
    while true; do
        echo -ne "  ${CYAN}[INPUT]${NC}   Enter root password: "
        read -rs ROOT_PASS; echo
        [[ -z "$ROOT_PASS" ]] && { warn "Password cannot be empty."; continue; }
        echo -ne "  ${CYAN}[INPUT]${NC}   Confirm root password: "
        read -rs ROOT_PASS2; echo
        [[ "$ROOT_PASS" == "$ROOT_PASS2" ]] && { success "Root password set."; break; }
        warn "Passwords do not match. Try again."
    done
}

# ============================================================
#  USER CREATION
# ============================================================
create_user() {
    step "User Account"
    echo -ne "  ${CYAN}[INPUT]${NC}   Enter username: "
    read -r USERNAME
    [[ -z "$USERNAME" ]] && error "Username cannot be empty."
    while true; do
        echo -ne "  ${CYAN}[INPUT]${NC}   Enter password for ${USERNAME}: "
        read -rs USER_PASS; echo
        [[ -z "$USER_PASS" ]] && { warn "Password cannot be empty."; continue; }
        echo -ne "  ${CYAN}[INPUT]${NC}   Confirm password: "
        read -rs USER_PASS2; echo
        [[ "$USER_PASS" == "$USER_PASS2" ]] && { success "User '${BOLD}${USERNAME}${NC}' configured."; break; }
        warn "Passwords do not match. Try again."
    done
}

# ============================================================
#  SYSTEM INFO
# ============================================================
set_system_info() {
    step "System Configuration"
    echo -ne "  ${CYAN}[INPUT]${NC}   Hostname [c-os]: "
    read -r HOSTNAME
    HOSTNAME="${HOSTNAME:-c-os}"
    success "Hostname: ${BOLD}${HOSTNAME}${NC}"
    echo

    local TIMEZONE_LIST=(
        "Europe/Istanbul"
        "UTC"
        "Europe/London"
        "Europe/Berlin"
        "Europe/Paris"
        "America/New_York"
        "America/Los_Angeles"
        "Asia/Tokyo"
        "Asia/Shanghai"
        "Custom"
    )
    local chosen_tz
    num_select chosen_tz "Select timezone:" "Enter timezone number" "${TIMEZONE_LIST[@]}"
    if [[ "$chosen_tz" == "Custom" ]]; then
        echo -ne "  ${CYAN}[INPUT]${NC}   Enter timezone (e.g. Europe/Paris): "
        read -r TIMEZONE
    else
        TIMEZONE="$chosen_tz"
    fi
    echo
    success "Timezone: ${BOLD}${TIMEZONE}${NC}"
}

# ============================================================
#  SUMMARY
# ============================================================
show_summary() {
    step "Installation Summary"
    echo -e "  ${BOLD}Disk        :${NC} ${TARGET_DISK}"
    echo -e "  ${BOLD}Boot mode   :${NC} ${BOOT_MODE}"
    echo -e "  ${BOLD}Hostname    :${NC} ${HOSTNAME}"
    echo -e "  ${BOLD}User        :${NC} ${USERNAME}"
    echo -e "  ${BOLD}Timezone    :${NC} ${TIMEZONE}"
    echo -e "  ${BOLD}Keymap      :${NC} ${KEYMAP}"
    echo -e "  ${BOLD}Desktop     :${NC} KDE Plasma"
    echo
    confirm "Start installation?" || { info "Installation cancelled."; exit 0; }
}

# ============================================================
#  PARTITIONING
# ============================================================
partition_disk() {
    step "Disk Partitioning"
    info "Partitioning ${TARGET_DISK}..."

    wipefs -af "${TARGET_DISK}" &>/dev/null
    sgdisk --zap-all "${TARGET_DISK}" &>/dev/null

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        parted -s "${TARGET_DISK}" \
            mklabel gpt \
            mkpart EFI  fat32  1MiB   513MiB \
            set 1 esp on \
            mkpart SWAP linux-swap 513MiB 2561MiB \
            mkpart ROOT ext4  2561MiB 100%

        EFI_PART="${TARGET_DISK}1"
        SWAP_PART="${TARGET_DISK}2"
        ROOT_PART="${TARGET_DISK}3"

        mkfs.fat  -F32 -n EFI  "${EFI_PART}"  &>/dev/null
        mkswap        -L SWAP  "${SWAP_PART}" &>/dev/null
        mkfs.ext4 -F  -L C_OS "${ROOT_PART}" &>/dev/null

        swapon "${SWAP_PART}"
        mount  "${ROOT_PART}" /mnt
        mkdir -p /mnt/boot/efi
        mount "${EFI_PART}" /mnt/boot/efi
    else
        parted -s "${TARGET_DISK}" \
            mklabel msdos \
            mkpart primary ext4       1MiB   513MiB \
            set 1 boot on \
            mkpart primary linux-swap 513MiB 2561MiB \
            mkpart primary ext4       2561MiB 100%

        BOOT_PART="${TARGET_DISK}1"
        SWAP_PART="${TARGET_DISK}2"
        ROOT_PART="${TARGET_DISK}3"

        mkfs.ext4 -F -L BOOT "${BOOT_PART}" &>/dev/null
        mkswap       -L SWAP "${SWAP_PART}" &>/dev/null
        mkfs.ext4 -F -L C_OS "${ROOT_PART}" &>/dev/null

        swapon "${SWAP_PART}"
        mount  "${ROOT_PART}" /mnt
        mkdir -p /mnt/boot
        mount "${BOOT_PART}" /mnt/boot
    fi

    success "Disk partitioned and mounted."
}

# ============================================================
#  BASE SYSTEM
# ============================================================
install_base() {
    step "Base System Installation"
    info "Running pacstrap, this may take a while..."

    pacstrap -K /mnt \
        base base-devel linux linux-firmware \
        grub efibootmgr os-prober \
        sudo \
        plasma-meta sddm kde-applications-meta \
        flatpak \
        xdg-desktop-portal xdg-desktop-portal-kde \
        xorg xorg-server \
        networkmanager \
        pipewire pipewire-alsa pipewire-pulse \
        wireplumber \
        nano vim htop neofetch \
        bash-completion \
        ntfs-3g dosfstools exfatprogs \
        firefox wget git \
        kitty \
        xdg-user-dirs xdg-utils \
        noto-fonts noto-fonts-emoji ttf-liberation \
        2>&1 | while IFS= read -r line; do
            echo -ne "  ${DIM}${line:0:72}${NC}\r"
        done

    echo
    success "Base packages installed."

    genfstab -L /mnt >> /mnt/etc/fstab
    success "fstab generated."
}

# ============================================================
#  C-OS Packages
# ============================================================
install_cos_assets() {
    step "C-OS Packages"

    info "Registering C-OS repository in pacman.conf."

    if ! grep -q "\[c-os\]" /mnt/etc/pacman.conf; then
cat >> /mnt/etc/pacman.conf << 'EOF'

[c-os]
SigLevel = Required DatabaseOptional
Server = https://canacikbas2010-blip.github.io/c-os-repo/$arch

EOF
    fi

    success "C-OS repository registered."

    arch-chroot /mnt pacman-key --init
    arch-chroot /mnt pacman-key --populate archlinux

    arch-chroot /mnt pacman -Syy --noconfirm

    arch-chroot /mnt pacman -S --noconfirm \
        papirus-icon-theme

    success "Papirus icon theme installed."
}

# ============================================================
#  CHROOT CONFIGURATION
# ============================================================
configure_system() {
    step "System Configuration"

    cat > /mnt/root/cos-chroot.sh << CHROOT_EOF
#!/bin/bash
set -e

# Locale
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Console keymap
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Services
systemctl enable NetworkManager
systemctl enable sddm

# Root password
echo "root:${ROOT_PASS}" | chpasswd

# User
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASS}" | chpasswd

# Sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Initramfs
mkinitcpio -P

# Bootloader
if [[ -d /sys/firmware/efi ]]; then
    grub-install --target=x86_64-efi \
                 --efi-directory=/boot/efi \
                 --bootloader-id="C-OS" \
                 --recheck
else
    grub-install --target=i386-pc ${TARGET_DISK} --recheck
fi

sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/'              /etc/default/grub
sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="C-OS"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# SDDM base config
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/kde.conf << 'SDDMEOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
SDDMEOF

echo "CHROOT_DONE"
CHROOT_EOF

    chmod +x /mnt/root/cos-chroot.sh

    arch-chroot /mnt /bin/bash -c "
        export TARGET_DISK='${TARGET_DISK}'
        /root/cos-chroot.sh
    " | while IFS= read -r line; do
        [[ "$line" == "CHROOT_DONE" ]] && success "System configuration complete." && continue
        echo -e "  ${DIM}${line}${NC}"
    done

    rm -f /mnt/root/cos-chroot.sh
}

# ============================================================
#  KDE THEME CONFIGURATION
# ============================================================
configure_kde_theme() {
    step "KDE Theme Configuration"

    local WALLPAPER
    WALLPAPER=$(find /mnt/usr/share/backgrounds -maxdepth 3 \
                \( -name "*.jpg" -o -name "*.png" \) 2>/dev/null | head -1)
    WALLPAPER="${WALLPAPER##/mnt}"

    info "Applying KDE theme settings for user: ${USERNAME}..."

    # KDE6 compat — detect kwriteconfig5 or kwriteconfig6
    arch-chroot /mnt /bin/bash << THEMEEOF
        export HOME=/home/${USERNAME}
        export USER=${USERNAME}
        export XDG_CONFIG_HOME=/home/${USERNAME}/.config

        KWRITE=\$(command -v kwriteconfig5 2>/dev/null || command -v kwriteconfig6 2>/dev/null || echo "")
        if [[ -z "\$KWRITE" ]]; then
            echo "[WARN] kwriteconfig not found, skipping KDE config writes."
        else
            # Icon theme — Papirus-Dark
            \$KWRITE --file kdeglobals --group Icons   --key Theme       'Papirus-Dark'

            # Plasma widget theme
            \$KWRITE --file plasmarc   --group Theme   --key name        'breeze-dark'

            # Color scheme
            \$KWRITE --file kdeglobals --group General --key ColorScheme 'BreezeDark'

            # Skel copies for future users
            mkdir -p /etc/skel/.config
            \$KWRITE --file /etc/skel/.config/kdeglobals --group Icons   --key Theme       'Papirus-Dark'
            \$KWRITE --file /etc/skel/.config/plasmarc   --group Theme   --key name        'breeze-dark'
            \$KWRITE --file /etc/skel/.config/kdeglobals --group General --key ColorScheme 'BreezeDark'
        fi

        # Wallpaper autostart — unquoted EOF so path expands correctly
        mkdir -p /home/${USERNAME}/.config/autostart
        cat > /home/${USERNAME}/.config/autostart/cos-wallpaper.desktop << EOF
[Desktop Entry]
Type=Application
Name=C-OS Wallpaper
Exec=plasma-apply-wallpaperimage ${WALLPAPER}
EOF

        chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
THEMEEOF
    2>&1 | while IFS= read -r line; do echo -e "  ${DIM}${line}${NC}"; done

    # GTK fallback — Papirus-Dark
    mkdir -p /mnt/etc/skel/.config/gtk-3.0
    cat > /mnt/etc/skel/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=breeze_cursors
gtk-font-name=Noto Sans 10
EOF
    success "GTK icon theme set: Papirus-Dark"

    # SDDM — activate breeze theme + set background
    mkdir -p /mnt/etc/sddm.conf.d

    cat > /mnt/etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=breeze
EOF
    success "SDDM theme activated: breeze"

    if [[ -n "$WALLPAPER" ]]; then
        cat >> /mnt/etc/sddm.conf.d/theme.conf << EOF
Background=${WALLPAPER}
EOF
        success "SDDM background set: $(basename "$WALLPAPER")"
    fi

    success "KDE theme configuration applied."
}

# ============================================================
#  FINALIZE
# ============================================================
finalize() {
    step "Finalizing"

    cat > /mnt/etc/motd << 'MOTD'

                                      ________________________________________________
                                     /                                                \
                                     |         ____           _____    ______         |
                                     |        / ___|         /  _  \  /  ___/         |
                                     |       | |      _____  | | | |  | |___          |
                                     |       | |     |_____| | | | |  \___  \         |
                                     |       | |___          | |_| |   ___)  |        |
                                     |        \____|         \_____/ /_____ /         |
                                     |                                                |
                                     |              Welcome to C-OS                   |
                                     ==================================================

MOTD

    cat > /mnt/etc/os-release << EOF
NAME="C-OS"
PRETTY_NAME="C-OS"
ID=c-os
ID_LIKE=arch
ANSI_COLOR="0;36"
BUILD_ID=$(date +%Y%m%d)
EOF

    arch-chroot /mnt xdg-user-dirs-update &>/dev/null || true
    arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" \
        "/home/${USERNAME}" &>/dev/null || true

    sync
    umount -R /mnt
    success "Filesystems unmounted."
}

# ============================================================
#  COMPLETION
# ============================================================
show_done() {
    clear
    show_banner
    echo -e "  ${GREEN}${BOLD}+--------------------------------------------------+"
    echo -e "  |         C-OS INSTALLATION COMPLETE               |"
    echo -e "  +--------------------------------------------------+${NC}"
    echo
    echo -e "  ${BOLD}Username    :${NC} ${USERNAME}"
    echo -e "  ${BOLD}Hostname    :${NC} ${HOSTNAME}"
    echo -e "  ${BOLD}Keymap      :${NC} ${KEYMAP}"
    echo -e "  ${BOLD}Timezone    :${NC} ${TIMEZONE}"
    echo -e "  ${BOLD}Desktop     :${NC} KDE Plasma"
    echo -e "  ${BOLD}Boot mode   :${NC} ${BOOT_MODE}"
    echo -e "  ${BOLD}Disk        :${NC} ${TARGET_DISK}"
    echo
    echo -e "  ${DIM}You can now reboot the system.${NC}"
    echo -e "  ${DIM}To exit the live environment run: ${CYAN}reboot${NC}"
    echo
}

# ============================================================
#  MAIN
# ============================================================
main() {
    show_banner
    pre_check
    select_disk
    select_keymap
    set_root_password
    create_user
    set_system_info
    show_summary
    partition_disk
    install_base
    install_cos_assets
    configure_system
    configure_kde_theme
    finalize
    show_done
}

main "$@"
