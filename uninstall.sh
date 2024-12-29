#!/bin/env bash
# 
# Mirrorsync - uninstall.sh
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
COMPLETE_ARG=0

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

  --complete
    Ensures that the configurations are removed as well

  -c <path>, --config-path <path>, --config-path=<path>
    The location where the configuration files of Mirrorsync are to be installed.
    Default: $DEFAULT_CONFIGDIR

  -i <path>, --installation-path <path>, --installation-path=<path>
    The location where the main script of Mirrorsync is installed.
    Default: $DEFAULT_INSTALLDIR

  -e <path>, --excludes-path <path>, --excludes-path=<path>
    The location where the scripts exclude files are to be added.
    Default: ${DEFAULT_INSTALLDIR}/excludes
EOF
}

# Arguments Parser
while [ "$#" -gt 0 ]; do
    arg=$1
    case $1 in
        # Convert "--opt=value" to --opt "value"
        --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
        --complete) COMPLETE_ARG=1; log "Complete argument is set, everything will be removed";;
        -c|--config-path) shift; CONFIGDIR=$1; log "Configuration path set to: $1";;
        -h|--help) usage; exit 0;;
        -i|--install-path) shift; INSTALLDIR=$1; log "Installation path set to: $1";;
        -e|--excludes-path) shift; EXCLUDESDIR=$1; log "Excludes path set to: $1";;
        -l|--log-path) shift; LOGDIR=$1; log "Log path set to: $1";;
        --) shift; break;;
        -*) error_argument "Unknown option: '$1'";;
        *) break;;
    esac
    shift || error_argument "Option '${arg}' requires a value"
done

# Start removing the directories
log "Removing the directory \"${EXCLUDEDIR}\" and its content"
rm -r "$EXCLUDESDIR"
log "Removing the directory \"${INSTALLDIR}\" and its content"
rm -r "$INSTALLDIR"

if [ $COMPLETE_ARG -eq 1 ]; then 
    log "Removing the directory \"${CONFIGDIR}\" and its content"
    rm -r "$CONFIGDIR"
fi

log "Mirrorsync is now removed"
log "Exiting..."
exit 0