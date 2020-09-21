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

