#!/bin/env bash
# 
# Mirrorsync
# By: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

CONFIG_FILE="/etc/mirrorsync/mirrorsync.conf"
REPO_CONFIG_DIR="/etc/mirrorsync/repos.conf.d"

# Verify config file is readable
if [ ! -r "$CONFIG_FILE" ]; then
    echo "$CONFIG_FILE is not availble or readable, exiting..."
    exit 1
fi

# Check if current path is writable

# Read settings
