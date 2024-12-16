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

# Log functions for standard output
log_stdout() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }
info_stdout() { log_stdout "$*" >&2; }
warning_stdout() { log_stdout "Warning: $*" >&2; }
error_stdout() { log_stdout "Error: $*" >&2; }
fatal_stdout() { error_stdout "$*, exiting..."; exit 1; }
argerror_stdout() { error_stdout "$*, exiting..."; usage >&2; exit 1; }

# Arguments Help
usage() {
    cat << EOF
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

# Arguments Parser
while [ "$#" -gt 0 ]; do
    arg=$1
    case $1 in
        # Convert "--opt=value" to --opt "value"
        --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
        -d|--destination) shift; DST=$1; info_stdout "Destination set to: $1";;
        -u|--user) shift; USER=$1; info_stdout "User set to: $1";;
        -g|--group) shift; GROUP=$1; info_stdout "Group set to: $1";;
        -h|--help) usage; exit 0;;
        --) shift; break;;
        -*) argerror_stdout "Unknown option: '$1'";;
        *) break;;
    esac
    shift || argerror_stdout "Option '${arg}' requires a value"
done

# Recive full path to this script
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
SRC="${SCRIPTDIR}/opt/mirrorsync/"

info_stdout "Synchronization process started at $DST"
# Using rsync to update script folder
rsync -a --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rwx,Fg=rx,Fo=rx "$SRC" "$DST"
info_stdout "Synchronization process finished, continuing with ownership"

# Fix the .version file to readonly
chmod u=r,g=r,o=r "${DST}/.version"

# If both group and user is set we can combine them
if [ ! -z "$USER" ] && [ ! -z "$GROUP" ]; then USER="${USER}:${GROUP}"; fi

# Change ownership on files if it is set
if [ ! -z "$USER" ]; then 
    chown -R "$USER" "$DST" 
    info_stdout "Added ownership $USER for $DST"
elif [ ! -z "$GROUP" ]; then
    chgrp -R "$GROUP" "$DST"
    info_stdout "Added ownership group $GROUP for $DST"
fi

VERSION=$(cat ${DST}/.version)
info_stdout "Update finished, current version is now: $VERSION"
info_stdout "Exiting..."
exit 0