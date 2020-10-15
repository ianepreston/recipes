#!/usr/bin/env bash

# Provision localhost with Ansible

INVENTORY="./inventory/local.yml"

echo $INVENTORY
ansible-playbook -i $INVENTORY main.yml