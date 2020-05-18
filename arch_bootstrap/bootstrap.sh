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