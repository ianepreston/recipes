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
