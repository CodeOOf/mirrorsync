#!/bin/env bash
# 
# Mirrorsync - update.sh
# Author: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

DST="/opt/mirrorsync"
USER=""
GROUP=""

usage() {
    cat <<EOF
Usage: $0 [options]

Arguments:

  -h, --help
    Display this usage message and exit.

  -d <path>, --destination <path>, --destination=<path>
    The custom location where the main script of Mirrorsync is installed.
    Default: /opt/mirrorsync

  -u <user>, --user <user>, --user=<user>
    Option to define a specific user that will use this script.
    Default: Current User

  -g <group>, --group <group>, --group=<group>
    Option to define a group that will have access to the installation.
    Default: Current User
EOF
}


# Parse Arguments
while [ "$#" -gt 0 ]; do
    arg=$1
    case $1 in
        # Convert "--opt=value" to --opt "value"
        --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
        -d|--destination) shift; DST=$1;;
        -u|--user) shift; USER=$1;;
        -g|--group) shift; GROUP=$1;;
        -h|--help) usage; exit 0;;
        --) shift; break;;
        -*) usage_fatal "unknown option: '$1'";;
        *) break;;
    esac
    shift || echo "Error: option '${arg}' requires a value"
done

# Recive full path to this script
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
SRC="${SCRIPTDIR}/opt/mirrorsync/"

# Using rsync to update script folder
rsync -a --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rwx,Fg=rx,Fo=rx "$SRC" "$DST"

# Fix the .version file to readonly
chmod u=r,g=r,o=r "${DST}/.version"

# If both group and user is set we can combine them
if [ ! -z "$USER" && ! -z "$GROUP" ]; then USER="${USER}:${GROUP}"

# Change ownership on files if it is set
if [ ! -z "$USER" ]; then 
    chown -R "$USER" "$DST" 
elif [ ! -z "$GROUP" ]; then
    chgrp -R "$GROUP" "$DST"
fi

exit 0