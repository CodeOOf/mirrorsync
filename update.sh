#!/bin/env bash
# 
# Mirrorsync - update.sh
# Author: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

# Recive full path to this script
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
CHANGELOG="${SCRIPTDIR}/CHANGELOG.md"
SRC="${SCRIPTDIR}/opt/mirrorsync/"
DST="/opt/mirrorsync"
USER=""
GROUP=""
NEW_VERSION=$(cat "${SRC}/.version")
OLD_VERSION=$(cat "${DST}/.version")

# Log functions
log() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }
info() { log "$*" >&2; }
warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { error "$*, exiting..."; exit 1; }
error_argument() { error "$*, exiting..."; usage >&2; exit 1; }

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
        -d|--destination) shift; DST=$1; info "Destination set to: $1";;
        -u|--user) shift; USER=$1; info "User set to: $1";;
        -g|--group) shift; GROUP=$1; info "Group set to: $1";;
        -h|--help) usage; exit 0;;
        --) shift; break;;
        -*) error_argument "Unknown option: '$1'";;
        *) break;;
    esac
    shift || error_argument "Option '${arg}' requires a value"
done

info "Synchronization process started at $DST"
# Using rsync to update script folder
rsync -a --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rwx,Fg=rx,Fo=rx "$SRC" "$DST"
info "Synchronization process finished, continuing with ownership"

# Fix the .version file to readonly
chmod 444 "${DST}/.version"
chmod 554 "${DST}/mirrorsync.sh"
chmod 554 "${DST}/httpsync.sh"

# If both group and user is set we can combine them
if [ ! -z "$USER" ] && [ ! -z "$GROUP" ]; then USER="${USER}:${GROUP}"; fi

# Change ownership on files if it is set
if [ ! -z "$USER" ]; then 
    chown -R "$USER" "$DST" 
    info "Added ownership $USER for $DST"
elif [ ! -z "$GROUP" ]; then
    chgrp -R "$GROUP" "$DST"
    info "Added ownership group $GROUP for $DST"
fi

# Verify that the version was added at the destination
VERSION=$(cat "${DST}/.version")
if [ "$VERSION" != "$NEW_VERSION" ]; then
    fatal "The new version \"${NEW_VERSION}\" is not found at \"${DST}\", update failed"
fi

info "Update finished, current version is now $VERSION"
info "Changes made since the old version ${OLD_VERSION}:"

# Print out changes since last update
re_header='^#.*'
re_blankline='^\s*$'
re_bullet='^\*.*'
start_arg=0
last_line=""

# Walk through the changelog and print out all the lines between releases
while read -r line; do
    # Skip blank lines
    if [[ "$line" =~ $re_blankline ]]; then continue; fi

    # First check if markdown header, else print change if the new version is found
    if [[ "$line" =~ $re_header ]]; then
        if [[ "$line" == *"${NEW_VERSION:1}"* ]]; then
            start_arg=1
        elif [[ "$line" == *"${OLD_VERSION:1}"* ]]; then
            info "$last_line"
            break
        fi
    elif [ $start_arg -eq 1 ]; then
        if [[ "$line" =~ $re_bullet ]]; then
            if [ ! -z "$last_line" ]; then 
                info "$last_line"
            fi
            last_line="$line"
        else
            # Sometimes the bullets are on multiple lines
            last_line+=" $line"
        fi
    fi
done < "$CHANGELOG"

# Done
info "Exiting..."
exit 0