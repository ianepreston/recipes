#!/usr/bin/env bash

# To install: bash <(curl -fsSL http://bootstrap.ianpreston.ca)

SOURCED=false && [ "${0}" = "${BASH_SOURCE[0]}" ] || SOURCED=true
if ! $SOURCED; then
  set -eEu
  shopt -s extdebug
  trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR
  IFS=$'\n\t'
fi

# Text modifiers
Bold="\033[1m"
Reset="\033[0m"

# Colors
Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"

# Paths
WORKING_DIR=$(pwd)
LOG="${WORKING_DIR}/arch-install.log"
[[ -f ${LOG} ]] && rm -f "${LOG}"
echo "Start log..." >>"${LOG}"

# Flags and variables
SYS_ARCH=$(uname -m) # Architecture (x86_64)
UEFI=0
XPINGS=0 # CONNECTION CHECK
KEYMAP="us"

# User provided variables
HOST_NAME="computer"
KERNEL_VERSION="default"
DUAL_DISK=0
MAIN_DISK="/dev/sda"
SECOND_DISK=""
ROOT_PWD=""
ANSIBLE_PWD=""


### Common Helper Functions

print_line() {
  printf "%$(tput cols)s\n" | tr ' ' '-' |& tee -a "${LOG}"
}

blank_line() {
  echo -e "\n" |& tee -a "${LOG}"
}

print_title() {
  clear
  print_line
  echo -e "# ${Bold}$1${Reset}" |& tee -a "${LOG}"
  print_line
  echo "" |& tee -a "${LOG}"
}

print_title_info() {
  T_COLS=$(tput cols)
  echo -e "${Bold}$1${Reset}\n" | fold -sw $((T_COLS - 18)) | sed 's/^/\t/' |& tee -a "${LOG}"
}

print_status() {
  T_COLS=$(tput cols)
  echo -e "$1${Reset}" | fold -sw $((T_COLS - 1)) |& tee -a "${LOG}"
}

print_info() {
  T_COLS=$(tput cols)
  echo -e "${Bold}$1${Reset}" | fold -sw $((T_COLS - 1)) |& tee -a "${LOG}"
}

print_warning() {
  T_COLS=$(tput cols)
  echo -e "${Yellow}$1${Reset}" | fold -sw $((T_COLS - 1)) |& tee -a "${LOG}"
}

print_success() {
  T_COLS=$(tput cols)
  echo -e "${Green}$1${Reset}" | fold -sw $((T_COLS - 1)) |& tee -a "${LOG}"
}

error_msg() {
  T_COLS=$(tput cols)
  echo -e "${Red}$1${Reset}\n" | fold -sw $((T_COLS - 1)) |& tee -a "${LOG}"
  exit 1
}

pause_function() {
  print_line
  read -re -sn 1 -p "Press enter to continue..."
}

invalid_option() {
  print_line
  print_warning "Invalid option. Try again."
}

contains_element() {
  #check if an element exist in a string
  for e in "${@:2}"; do [[ $e == "$1" ]] && break; done
}

print_summary() {
  print_title "Summary"
  print_title_info "Below is a summary of your selections and any auto-detected system information.  If anything is wrong cancel out now with Ctrl-C.  If you continue the installation will begin and there will be no more input required."
  print_line
  if [[ $UEFI == 1 ]]; then
    print_status "The machine architecture is $SYS_ARCH and UEFI has been found."
  else
    print_status "The machine architecture is $SYS_ARCH and a BIOS has been found."
  fi

  print_status "The hostname selected is $HOST_NAME"

  case "$KERNEL_VERSION" in
  "lts")
    print_status "The LTS kernel will be installed."
    ;;
  "hard")
    print_status "The hardened kernel will be installed."
    ;;
  *)
    print_status "The default kernel will be installed."
    ;;
  esac

  blank_line
  if [[ $DUAL_DISK == 0 ]]; then
    print_status "This is a single disk system so installation of all files will happen to $MAIN_DISK."
  else
    print_status "This is a dual disk system."
    print_status "The main disk is $MAIN_DISK."
    print_status "The second disk is $SECOND_DISK."
  fi

  blank_line
  pause_function
}

arch_chroot() {
  arch-chroot /mnt /bin/bash -c "${1}" |& tee -a "${LOG}"
}

is_package_installed() {
  #check if a package is already installed
  for PKG in $1; do
    pacman -Q "$PKG" &>/dev/null && return 0
  done
  return 1
}

### Verification Functions

check_root() {
  print_info "Checking root permissions..."

  if [[ "$(id -u)" != "0" ]]; then
    error_msg "ERROR! You must execute the script as the 'root' user."
  fi
}

check_archlinux() {
  if [[ ! -e /etc/arch-release ]]; then
    error_msg "ERROR! You must execute the script on Arch Linux."
  fi
}

check_boot_system() {
  if [[ "$(cat /sys/class/dmi/id/sys_vendor)" == 'Apple Inc.' ]] || [[ "$(cat /sys/class/dmi/id/sys_vendor)" == 'Apple Computer, Inc.' ]]; then
    modprobe -r -q efivars || true # if MAC
  else
    modprobe -q efivarfs # all others
  fi

  if [[ -d "/sys/firmware/efi/" ]]; then
    ## Mount efivarfs if it is not already mounted
    # shellcheck disable=SC2143
    if [[ -z $(mount | grep /sys/firmware/efi/efivars) ]]; then
      mount -t efivarfs efivarfs /sys/firmware/efi/efivars
    fi
    UEFI=1
  else
    UEFI=0
  fi
}


### Prompts and User Interaction

ask_for_hostname() {
  print_title "Hostname"
  print_title_info "Pick a hostname for this machine.  Press enter to have a random hostname selected."
  read -rp "Hostname [ex: archlinux]: " HOST_NAME
  if [[ $HOST_NAME == "" ]]; then
    HOST_NAME="arch-$((1 + RANDOM % 1000)).tts.lan"
  fi
}


ask_for_main_disk() {
  print_info "Determining main disk..."
  devices_list=($(lsblk --nodeps --noheading --list --exclude 1,11,7 | awk '{print "/dev/" $1}'))

  if [[ ${#devices_list[@]} == 1 ]]; then
    device=${devices_list[0]}
  else
    print_title "Main Disk Selection"
    print_title_info "Select which disk to use for the main installation (where root and boot will go)."
    lsblk --nodeps --list --exclude 1,11,7 --output "name,size,type"
    blank_line
    PS3="Enter your option: "
    echo -e "Select main drive:\n"
    select device in "${devices_list[@]}"; do
      if contains_element "${device}" "${devices_list[@]}"; then
        break
      else
        invalid_option
      fi
    done
  fi
  MAIN_DISK=$device
}

ask_for_kernel_level() {
  print_title "Kernel Selection"
  print_title_info "Select which linux kernel to install. The LTS version is generally prefered and more stable."
  version_list=("linux (default kernel)" "linux-lts (long term support, recommended)" "linux-hardened (security features)")
  blank_line
  PS3="Enter your option: "
  echo -e "Select linux version to install\n"
  select VERSION in "${version_list[@]}"; do
    if contains_element "$VERSION" "${version_list[@]}"; then
      if [ "linux (default kernel)" == "$VERSION" ]; then
        KERNEL_VERSION="default"
      elif [ "linux-lts (long term support, recommended)" == "$VERSION" ]; then
        KERNEL_VERSION="lts"
      elif [ "linux-hardened (security features)" == "$VERSION" ]; then
        KERNEL_VERSION="hard"
      fi
      break
    else
      invalid_option
    fi
  done
}

ask_for_root_password() {
  print_title "Root Password"
  print_title_info "Set the password for the root account."

  local was_set="false"

  blank_line
  while [[ $was_set == "false" ]]; do
    local pwd1=""
    local pwd2=""
    read -srp "Root password: " pwd1
    echo -e ""
    read -srp "Once again: " pwd2

    if [[ $pwd1 == "$pwd2" ]]; then
      ROOT_PWD="$pwd1"
      was_set="true"
    else
      blank_line
      print_warning "They didn't match... try again."
    fi
  done
}


ask_for_ansible_password() {
  print_title "Ansible Password"
  print_title_info "This script sets up an account to run Ansible scripts.  Set the password of that account."

  local was_set="false"

  blank_line
  while [[ $was_set == "false" ]]; do
    local pwd1=""
    local pwd2=""
    read -srp "Ansible password: " pwd1
    echo -e ""
    read -srp "Once again: " pwd2

    if [[ $pwd1 == "$pwd2" ]]; then
      ANSIBLE_PWD="$pwd1"
      was_set="true"
    else
      blank_line
      print_warning "They didn't match... try again."
    fi
  done
}

### Installation/configuration functions

configure_mirrorlist() {
  print_info "Configuring repository mirrorlist"

  pacman -Syy |& tee -a "${LOG}"

  # Install reflector
  pacman -S --noconfirm reflector |& tee -a "${LOG}"

  print_status "    Backing up the original mirrorlist..."
  rm -f "/etc/pacman.d/mirrorlist.orig" |& tee -a "${LOG}"
  mv -i "/etc/pacman.d/mirrorlist" "/etc/pacman.d/mirrorlist.orig" |& tee -a "${LOG}"

  print_status "    Rotating the new list into place..."
  # Run reflector
  /usr/bin/reflector --score 100 --fastest 20 --age 12 --sort rate --protocol https --save /etc/pacman.d/mirrorlist |& tee -a "${LOG}"

  # Allow global read access (required for non-root yaourt execution)
  chmod +r /etc/pacman.d/mirrorlist |& tee -a "${LOG}"

  # Update one more time
  pacman -Syy |& tee -a "${LOG}"
}


unmount_partitions() {
  mounted_partitions=($(lsblk | grep /mnt | awk '{print $7}' | sort -r))
  swapoff -a
  for i in "${mounted_partitions[@]}"; do
    umount "$i"
  done
}

find_boot_partition() {
  print_title "Boot partition selection"
  print_title_info "Select the partition to use for boot. This should be an already existing boot partition. If you don't see what you expect here STOP and run cfdisk or something to figure it out."
  partition_list=($(lsblk $MAIN_DISK --noheading --list --output NAME | awk '{print "/dev/" $1}' | grep "[0-9]$"))
  blank_line
  PS3="Enter your option":
  lsblk $MAIN_DISK --output NAME,FSTYPE,LABEL,SIZE
  echo -e "select a partition"
  select partition in "${partition_list[@]}"; do
    if contains_element "$partition" "${partition_list[@]}"; then
      break
    else
      invalid_option
    fi
  done
  BOOT_PARTITION=$partition
}

find_install_partition() {
  print_title "Installation partition selection"
  print_title_info "Select the partition to install Arch. This should be an already existing boot partition. If you don't see what you expect here STOP and run cfdisk or something to figure it out."
  partition_list=($(lsblk $MAIN_DISK --noheading --list --output NAME | awk '{print "/dev/" $1}' | grep "[0-9]$"))
  blank_line
  PS3="Enter your option":
  lsblk $MAIN_DISK --output NAME,FSTYPE,LABEL,SIZE
  echo -e "select a partition"
  select partition in "${partition_list[@]}"; do
    if contains_element "$partition" "${partition_list[@]}"; then
      break
    else
      invalid_option
    fi
  done
  INSTALL_PARTITION=$partition
}

setup_lvm() {
  print_info "Setting up LVM"

  # For real, we're wiping disks here, I hope you picked the right one
  pvcreate $INSTALL_PARTITION -ffy
  vgcreate "vg_main" $INSTALL_PARTITION

  lvcreate -l 10%VG "vg_main" -n lv_var
  lvcreate -l 40%VG "vg_main" -n lv_root
  lvcreate -l 40%VG "vg_main" -n lv_home
}

format_partitions() {
  print_info "Formatting partitions"

  mkfs.ext4 "/dev/mapper/vg_main-lv_var"
  mkfs.ext4 "/dev/mapper/vg_main-lv_root"
  mkfs.ext4 "/dev/mapper/vg_main-lv_home"
}

mount_partitions() {
  print_info "Mounting partitions"

  # First load the root
  mount -t ext4 -o defaults,rw,relatime,errors=remount-ro /dev/mapper/vg_main-lv_root /mnt

  # Create the paths for the other mounts
  mkdir -p "/mnt/boot/efi"
  mkdir -p "/mnt/var"
  mkdir -p "/mnt/home"

  if [[ $UEFI == 1 ]]; then
    mount -t vfat -o defaults,rw,relatime,utf8,errors=remount-ro "${MAIN_DISK}1" "/mnt/boot/efi"
  fi

  # Mount others
  mount -t ext4 -o defaults,rw,relatime /dev/mapper/vg_main-lv_var /mnt/var
  mount -t ext4 -o defaults,rw,relatime /dev/mapper/vg_main-lv_home /mnt/home
}

install_base_system() {
  print_info "Installing base system"

  pacman -S --noconfirm archlinux-keyring |& tee -a "${LOG}"

  # Install kernel
  case "$KERNEL_VERSION" in
  "lts")
    pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware |& tee -a "${LOG}"
    [[ $? -ne 0 ]] && error_msg "Installing base system to /mnt failed. Check error messages above."
    ;;
  "hard")
    pacstrap /mnt base base-devel linux-hardened linux-hardened-headers linux-firmware |& tee -a "${LOG}"
    [[ $? -ne 0 ]] && error_msg "Installing base system to /mnt failed. Check error messages above."
    ;;
  *)
    pacstrap /mnt base base-devel linux linux-headers linux-firmware |& tee -a "${LOG}"
    [[ $? -ne 0 ]] && error_msg "Installing base system to /mnt failed. Check error messages above."
    ;;
  esac

  # Install file system tools
  pacstrap /mnt lvm2 dosfstools mtools gptfdisk |& tee -a "${LOG}"
  [[ $? -ne 0 ]] && error_msg "Installing base system to /mnt failed. Check error messages above. Part 4."

  # Install networking tools
  pacstrap /mnt dialog networkmanager networkmanager-openvpn iw wireless_tools wpa_supplicant |& tee -a "${LOG}"
  [[ $? -ne 0 ]] && error_msg "Installing base system to /mnt failed. Check error messages above. Part 5."

  # Remaining misc tools
  pacstrap /mnt reflector git gvim openssh ansible terminus-font systemd-swap |& tee -a "${LOG}"
  [[ $? -ne 0 ]] && error_msg "Installing base system to /mnt failed. Check error messages above. Part 6."

  # Add the ssh group
  arch_chroot "groupadd ssh"

  # Set the NetworkManager & ssh services to be enabled
  arch_chroot "systemctl enable NetworkManager.service"
  arch_chroot "systemctl enable wpa_supplicant.service"
  arch_chroot "systemctl enable sshd.service"
}

configure_keymap() {
  print_info "Configure keymap"
  echo "KEYMAP=$KEYMAP" >/mnt/etc/vconsole.conf
  echo "FONT=ter-120n" >>/mnt/etc/vconsole.conf
}

configure_fstab() {
  print_info "Write fstab"

  genfstab -U -p /mnt >/mnt/etc/fstab
}

configure_hostname() {
  print_info "Setup hostname"

  echo "$HOST_NAME" >/mnt/etc/hostname

  # Add the lines in case they are not in the file...
  arch_chroot "grep -q '^127.0.0.1\s' /etc/hosts || echo '127.0.0.1  temp' >> /etc/hosts"
  arch_chroot "grep -q '^::1\s' /etc/hosts || echo '::1  temp' >> /etc/hosts"
  arch_chroot "grep -q '^127.0.1.1\s' /etc/hosts || echo '127.0.1.1  temp' >> /etc/hosts"
  # Now put in the proper values
  arch_chroot "sed -i 's/^127.0.0.1\s.*$/127.0.0.1  localhost/' /etc/hosts"
  arch_chroot "sed -i 's/^::1\s.*$/::1  localhost/' /etc/hosts"
  arch_chroot "sed -i 's/^127.0.1.1\s.*$/127.0.1.1  '${HOST_NAME}' '${HOST_NAME%%.*}'/' /etc/hosts"
}

configure_timezone() {
  print_info "Configuring timezone"

  arch_chroot "ln -sf /usr/share/zoneinfo/Canada/Mountain /etc/localtime"
  arch_chroot "sed -i '/#NTP=/d' /etc/systemd/timesyncd.conf"
  arch_chroot "sed -i 's/#Fallback//' /etc/systemd/timesyncd.conf"
  arch_chroot 'echo "FallbackNTP=0.pool.ntp.org 1.pool.ntp.org 0.us.pool.ntp.org" >> /etc/systemd/timesyncd.conf'
  arch_chroot "systemctl enable systemd-timesyncd.service"
}

configure_locale() {
  print_info "Configuring locale"
  echo 'LANG="en_CA.UTF-8"' >/mnt/etc/locale.conf
  echo 'LANGUAGE="en_CA:en"' >>/mnt/etc/locale.conf
  echo 'LC_ALL="en_CA.UTF-8"' >>/mnt/etc/locale.conf
  arch_chroot "sed -i 's/# en_CA.UTF-8/en_CA.UTF-8/' /etc/locale.gen"
  arch_chroot "sed -i 's/#en_CA.UTF-8/en_CA.UTF-8/' /etc/locale.gen"
  arch_chroot "locale-gen"
}

configure_mkinitcpio() {
  print_info "Configuring mkinitcpio"

  sed -i '/^HOOKS/c\HOOKS=(systemd keyboard autodetect modconf block sd-vconsole sd-encrypt sd-lvm2 filesystems fsck)' /mnt/etc/mkinitcpio.conf |& tee -a "${LOG}"

  # Setup compression
  sed -i 's/#COMPRESSION="lz4"/COMPRESSION="lz4"/' /mnt/etc/mkinitcpio.conf |& tee -a "${LOG}"
  sed -i '/^#COMPRESSION_OPTIONS/c\COMPRESSION_OPTIONS=(-3)' /mnt/etc/mkinitcpio.conf |& tee -a "${LOG}"

  arch_chroot "mkinitcpio -P"
}

configure_systemd_swap() {
  print_info "Configuring systemd-swap"

  arch_chroot "systemctl enable systemd-swap.service"

  arch_chroot 'echo -e "zswap_enabled=1\nzram_enabled=0\nswapfc_enabled=1" > /etc/systemd/swap.conf.d/swap-config.conf'
}

install_bootloader() {
  print_info "Install bootloader"

  if [[ $UEFI == 1 ]]; then
    pacstrap /mnt grub os-prober breeze-grub |& tee -a "${LOG}"
    [[ $? -ne 0 ]] && error_msg "Installing base system to /mnt failed. Check error messages above. Part 7."
  else
    pacstrap /mnt grub-bios os-prober breeze-grub |& tee -a "${LOG}"
    [[ $? -ne 0 ]] && error_msg "Installing base system to /mnt failed. Check error messages above. Part 8."
  fi

  if [[ $UEFI == 1 ]]; then
    pacstrap /mnt efibootmgr |& tee -a "${LOG}"
  fi
}

configure_bootloader() {
  print_info "Configure bootloader"

  if [[ $UEFI == 1 ]]; then
    arch_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub --recheck"
  else
    arch_chroot "grub-install --target=i386-pc --recheck --debug /dev/sda"
  fi

  # Update grub config
  sed -i '/^GRUB_TIMEOUT/c\GRUB_TIMEOUT=5' /mnt/etc/default/grub |& tee -a "${LOG}"
  # shellcheck disable=SC2016
  sed -i '/^GRUB_DISTRIBUTOR/c\GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Arch`' /mnt/etc/default/grub |& tee -a "${LOG}"
  sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT/c\GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' /mnt/etc/default/grub |& tee -a "${LOG}"
  sed -i '/^GRUB_GFXMODE/c\GRUB_GFXMODE=1024x768x32,1024x768x24,1024x768,auto' /mnt/etc/default/grub |& tee -a "${LOG}"
  sed -i '/^GRUB_DISABLE_RECOVERY/c\#GRUB_DISABLE_RECOVERY=true' /mnt/etc/default/grub |& tee -a "${LOG}"
  sed -i '/^GRUB_THEME/c\GRUB_THEME="/usr/share/grub/themes/breeze/theme.txt"' /mnt/etc/default/grub |& tee -a "${LOG}"
  sed -i '/^#GRUB_THEME/c\GRUB_THEME="/usr/share/grub/themes/breeze/theme.txt"' /mnt/etc/default/grub |& tee -a "${LOG}"
  sed -i '/^#GRUB_INIT_TUNE/c\GRUB_INIT_TUNE="480 440 1"' /mnt/etc/default/grub |& tee -a "${LOG}"

  # Make the config
  arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
}

configure_sudo() {
  print_info "Configuring sudo..."
  echo '%wheel ALL=(ALL) ALL' >>/mnt/etc/sudoers.d/wheel
  chmod 440 /mnt/etc/sudoers.d/wheel
}

configure_pacman() {
  print_info "Configuring pacman..."
  cp -v /mnt/etc/pacman.conf /mnt/etc/pacman.conf.orig

  setup_repo() {
    local _has_repo
    _has_repo=$(grep -n "\[$1\]" /mnt/etc/pacman.conf | cut -f1 -d:)
    if [[ -z $_has_repo ]]; then
      echo -e "\n[$1]\nInclude = /etc/pacman.d/mirrorlist" >>/mnt/etc/pacman.conf
    else
      sed -i "${_has_repo}s/^#//" /mnt/etc/pacman.conf
      _has_repo=$((_has_repo + 1))
      sed -i "${_has_repo}s/^#//" /mnt/etc/pacman.conf
    fi
  }

  sed -i '/^#Color/c\Color' /mnt/etc/pacman.conf |& tee -a "${LOG}"
  sed -i '/^#TotalDownload/c\TotalDownload' /mnt/etc/pacman.conf |& tee -a "${LOG}"
}

pull_repo() {
  print_info "Pulling repo"
  mkdir -p /mnt/srv/recipes
  arch_chroot "git clone https://github.com/ianepreston/recipes.git /srv/recipes"
  arch_chroot "chown -R ansible:ansible /srv/recipes"
}

root_password() {
  print_info "Setting up root account"

  arch_chroot "echo -n 'root:$ROOT_PWD' | chpasswd -c SHA512"
}

setup_ansible_account() {
  print_info "Setting up Ansible account"

  arch_chroot "useradd -m -G wheel -s /bin/bash ansible"

  arch_chroot "echo -n 'ansible:$ANSIBLE_PWD' | chpasswd -c SHA512"

  arch_chroot "chfn ansible -f Ansible"

  mkdir -p /mnt/home/ansible/.ssh
  chmod 0700 /mnt/home/ansible/.ssh
  arch_chroot "chown -R ansible:ansible /home/ansible/.ssh"

  # Add user to the ssh
  arch_chroot "usermod -a -G ssh ansible"
}

stamp_build() {
  print_info "Stamping build"
  # Stamp the build
  mkdir -p /mnt/srv/provision-stamps
  date --iso-8601=seconds | sudo tee /mnt/srv/provision-stamps/box_build_time
  cp "${LOG}" /mnt/srv/provision-stamps/arch-install.log
}

copy_mirrorlist() {
  print_info "Copying mirrorlist"

  # Backup the original
  rm -f "/mnt/etc/pacman.d/mirrorlist.orig"
  mv -i "/mnt/etc/pacman.d/mirrorlist" "/mnt/etc/pacman.d/mirrorlist.orig"

  # Copy ours over
  mv -i "/etc/pacman.d/mirrorlist" "/mnt/etc/pacman.d/mirrorlist"

  # Allow global read access (required for non-root yaourt execution)
  chmod +r /mnt/etc/pacman.d/mirrorlist
}

wrap_up() {
  print_title "INSTALL COMPLETED"
  print_success "After reboot you can configure users, install software."
  print_success "This script pulled its Github repo containing Ansible scripts to /srv/recipes."
  print_success "Generally after rebooting I run Ansible to fully install and configure the machine."
  blank_line
}


### Main flow
loadkeys "$KEYMAP" # load the keymap

print_title "https://github.com/ianepreston/recipes"
print_title_info "Provision Arch -> Automated script to install my Arch systems."
print_line
print_status "Script can be cancelled at any time with CTRL+C"
pause_function

check_root
check_archlinux
check_boot_system

## Ask questions
ask_for_hostname
ask_for_main_disk
find_boot_partition
find_install_partition
ask_for_kernel_level
ask_for_root_password
ask_for_ansible_password

print_summary

configure_mirrorlist

unmount_partitions
setup_lvm
format_partitions
mount_partitions

install_base_system
configure_keymap
configure_fstab
configure_hostname
configure_timezone
configure_clock
configure_locale
configure_mkinitcpio
configure_systemd_swap

install_bootloader
configure_bootloader

configure_sudo
copy_mirrorlist
configure_pacman

root_password
setup_ansible_account
pull_repo
stamp_build

unmount_partitions
wrap_up