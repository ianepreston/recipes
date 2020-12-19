#!/usr/bin/env bash
ansible-galaxy collection install community.general

ansible-playbook main.yml --ask-become-pass
