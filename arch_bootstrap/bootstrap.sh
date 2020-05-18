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
