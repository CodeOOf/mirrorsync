#!/bin/env bash
# 
# Mirrorsync - install.sh
# Author: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

DEFAULT_INSTALLDIR="/opt/mirrorsync"
DEFAULT_CONFIGDIR="/etc/mirrorsync"
DEFAULT_EXCLUDESDIR="/opt/mirrorsync/excludes"
DEFAULT_LOGDIR="/var/log/mirrorsync"
INSTALLDIR="$DEFAULT_INSTALLDIR"
CONFIGDIR="$DEFAULT_CONFIGDIR"
EXCLUDESDIR="$DEFAULT_EXCLUDESDIR"
LOGDIR="$DEFAULT_LOGDIR"
USER=""
GROUP=""

# Log functions
log_stdout() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }
log() { log_stdout "$*" >&2; }
warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { log "$*, exiting..."; exit 1; }
error_argument() { log "$*, exiting..."; usage >&2; exit 1; }

# Arguments Help
usage() {
    cat << EOF
Usage: $0 [options]

Arguments:

  -h, --help
    Display this usage message and exit.

  -c <path>, --config-path <path>, --config-path=<path>
    The location where the configuration files of Mirrorsync are to be installed.
    Default: $DEFAULT_CONFIGDIR

  -i <path>, --installation-path <path>, --installation-path=<path>
    The location where the main script of Mirrorsync is installed.
    Default: $DEFAULT_INSTALLDIR

  -e <path>, --excludes-path <path>, --excludes-path=<path>
    The location where the scripts exclude files are to be added.
    Default: ${DEFAULT_INSTALLDIR}/excludes

  -g <group>, --group <group>, --group=<group>
    Option to define a group that will have access to the installation.
    Default: Current User

  -l <path>, --log-path <path>, --log-path=<path>
    The location where the configurationfiles of Mirrorsync is installed.
    Default: $DEFAULT_LOGDIR

  -u <user>, --user <user>, --user=<user>
    Option to define a specific user that will use this script.
    Default: Current User
EOF
}

# Arguments Parser
while [ "$#" -gt 0 ]; do
    arg=$1
    case $1 in
        # Convert "--opt=value" to --opt "value"
        --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
        -c|--config-path) shift; CONFIGDIR=$1; log "Configuration path set to: $1";;
        -h|--help) usage; exit 0;;
        -i|--install-path) shift; INSTALLDIR=$1; log "Installation path set to: $1";;
        -e|--excludes-path) shift; EXCLUDESDIR=$1; log "Excludes path set to: $1";;
        -g|--group) shift; GROUP=$1; log "Group set to: $1";;
        -l|--log-path) shift; LOGDIR=$1; log "Log path set to: $1";;
        -u|--user) shift; USER=$1; log "User set to: $1";;
        --) shift; break;;
        -*) error_argument "Unknown option: '$1'";;
        *) break;;
    esac
    shift || error_argument "Option '${arg}' requires a value"
done

# Recive full path to this script
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
SRC_INSTALLDIR="${SCRIPTDIR}/opt/mirrorsync"
SRC_CONFIGDIR="${SCRIPTDIR}/etc/mirrorsync"

REPOCONFIGDIR="${CONFIGDIR}/repos.conf.d"
SRC_REPOCONFIGDIR="${SRC_CONFIGDIR}/repos.conf.d"

# If the default installation path has changed then the default for excludes path changed
if [ "$INSTALLDIR" != "$DEFAULT_INSTALLDIR" ]; then 
# And if no active action is done about the excludes path is also updated to match new defaults
    if [ "$EXCLUDESDIR" == "$DEFAULT_EXCLUDESDIR" ]; then
        DEFAULT_EXCLUDESDIR="${INSTALLDIR}/excludes"
        EXCLUDESDIR="$DEFAULT_EXCLUDESDIR"
        log "The excludes dir is set to \"${EXCLUDESDIR}\""
    else
        DEFAULT_EXCLUDESDIR="${INSTALLDIR}/excludes"
    fi
fi

# First create all the directories
log "Setting up all the directories..."
log "Creating the directory \"${REPOCONFIGDIR}\""
mkdir -p "$REPOCONFIGDIR"
log "Creating the directory \"${INSTALLDIR}\""
mkdir -p "$INSTALLDIR"
log "Creating the directory \"${EXCLUDESDIR}\""
mkdir -p "$EXCLUDESDIR"
log "Creating the directory \"${LOGDIR}\""
mkdir -p "$LOGDIR"

# Copy over the files
log "Copying over all the files to their destinations..."
log "Copying everything from \"${SRC_INSTALLDIR}\" into \"${INSTALLDIR}\""
cp "${SRC_INSTALLDIR}/" "${INSTALLDIR}"
log "Copying everything from \"${SRC_REPOCONFIGDIR}\" into \"${REPOCONFIGDIR}\""
cp "${SRC_REPOCONFIGDIR}/" "${REPOCONFIGDIR}"
log "Copying main configuration \"${SRC_CONFIGDIR}/mirrorsync.conf\" into \"${CONFIGDIR}/mirrorsync.conf\""
cp "${SRC_CONFIGDIR}/mirrorsync.conf" "${CONFIGDIR}/mirrorsync.conf"

# Fix the .version file to readonly
log "Setting up access rights"
chmod u=r,g=r,o=r "${INSTALLDIR}/.version"
chmod u=r,g=r+x,o=r+x "${INSTALLDIR}/mirrorsync.sh"
chmod u=r,g=r+x,o=r+x "${INSTALLDIR}/httpsync.sh"
chmod u=r,g=rwx,o=rwx "${EXCLUDESDIR}"
chmod u=r,g=rw,o=rw "${LOGDIR}"
chmod u=r,g=r+x,o=r+x "${REPOCONFIGDIR}"
chmod u=r+x,g=rwx,o=rwx "${CONFIGDIR}"


# If both group and user is set we can combine them
if [ ! -z "$USER" ] && [ ! -z "$GROUP" ]; then USER="${USER}:${GROUP}"; fi

# Change ownership on files if it is set
if [ ! -z "$USER" ]; then 
    chown -R "$USER" "$INSTALLDIR" 
    log "Added ownership $USER for $INSTALLDIR"

    chown -R "$USER" "$LOGDIR" 
    log "Added ownership $USER for $LOGDIR"

    chown -R "$USER" "$EXCLUDESDIR" 
    log "Added ownership $USER for $EXCLUDESDIR"
elif [ ! -z "$GROUP" ]; then
    chgrp -R "$GROUP" "$INSTALLDIR"
    log "Added ownership group $GROUP for $INSTALLDIR"

    chgrp -R "$GROUP" "$LOGDIR"
    log "Added ownership group $GROUP for $LOGDIR"

    chgrp -R "$GROUP" "$EXCLUDESDIR"
    log "Added ownership group $GROUP for $EXCLUDESDIR"
fi

# Construct the command
opts=()

if [ "$EXCLUDESDIR" != "$DEFAULT_EXCLUDESDIR" ]; then 
    opts+=(--excludes-path=$EXCLUDEDIR)
fi

if [ "$CONFIGDIR" != "$DEFAULT_CONFIGDIR" ]; then 
    opts+=(--config-path=$CONFIGDIR)
fi

VERSION=$(cat ${INSTALLDIR}/.version)
log "Installation finished, current version is now: $VERSION"
log "Update the configurations found at \"${CONFIGDIR}\" before running this script"
if [ "$LOGDIR" != "$DEFAULT_LOGDIR" ]; then 
    warning "Remember to update the \"${CONFIGDIR}/mirrorsync.sh\" with the non default log path: $LOGDIR"
fi
log "Usage:"
log "${INSTALLDIR}/mirrorsync.sh ${opts[@]}"
log "Advice the \"${SCRIPTDIR}/example.crontab\" for examples on how to set up the script for automated runs"
log "Exiting..."
exit 0