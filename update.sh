#!/bin/env bash
# 
# Mirrorsync - update.sh
# Author: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

# Argument validation check
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <Installation Path>"
    exit 1
fi

# Recive full path to script
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
SRC="${SCRIPTDIR}/opt/mirrorsync/"
DST="$1"

# Using rsync to update script folder
rsync -a --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rwx,Fg=rx,Fo=rx "$SRC" "$DST"

# Fix the .version file to readonly
chmod u=r,g=r,o=r "${DST}/.version"