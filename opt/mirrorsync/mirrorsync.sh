#!/bin/env bash
# 
# Mirrorsync - mirrorsync.sh
# Author: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

CONFIGFILE="/etc/mirrorsync/mirrorsync.conf"
REPOCONFIG_DIR="/etc/mirrorsync/repos.conf.d"
LOCKFILE="$0.lockfile"

HTTP_PORT=80
HTTPS_PORT=443
RSYNC_PORT=873

# Setup log functions before logfile validation
info_nolog() { printf "[%(%F %T)T] Info: %s\n" -1 "$*" >&2; }
fatal_nolog() { printf "[%(%F %T)T] Error: %s, exiting...\n" -1 "$*"; exit 1; }

# Verify config file is readable
if [ ! -r "$CONFIGFILE" ]; then
    fatal_nolog "The script configfile \"$CONFIGFILE\" is not availble or readable"
else
    source "$CONFIGFILE"
fi

# Verify repo path exists
if [ ! -d "$REPOCONFIG_DIR" ]; then
    fatal_nolog "The directory \"$REPOCONFIG_DIR\" does not exist"
fi

# Verify that there are any mirror repositories to work with
REPOCONFIGS=(${REPOCONFIG_DIR}/*.conf)
if [ "${#REPOCONFIGS[@]}" == 0 ]; then
    fatal_nolog "The directory \"$REPOCONFIG_DIR\" is empty or contains no config files, please provide repository 
config files that this script can work with"
fi

# Verify that current path is writable
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
if [ ! -w "$SCRIPTDIR" ]; then
    fatal_nolog "The directory where this script is located is not writable for this user. This is required for the 
lockfile to avoid multiple simultaneous runs of the script"
fi

# Validate current settings
if [ -z "$LOGPATH" ]; then 
    info_nolog "Missing variable \"LOGPATH\" at \"$CONFIGFILE\", using default"
    LOGPATH="/var/log/mirrorsync"
fi

if [ ! -w "$LOGPATH" ]; then
    fatal_nolog "The log directory is not writable for this user: $LOGPATH"
fi

if [ -z "$LOGFILENAME" ]; then 
    info_nolog "Missing variable \"LOGFILENAME\" at \"$CONFIGFILE\", using default"
    LOGFILENAME="$0"
fi
LOGFILE="${LOGPATH}/${LOGFILENAME}.log"

# Setup log functions when logfile is availble
log() { printf "[%(%F %T)T] %s\n" -1 "$*" >> "$LOGFILE" 2>&1; }
info() { log "Info: $*" >&2; }
warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { error "$*, exiting..."; exit 1; }

if [ -z "$DSTPATH" ]; then 
    fatal "Missing variable \"DSTPATH\" at \"${CONFIGFILE}\". It is required to know where to write the mirror data"
fi

if [ ! -w "$DSTPATH" ]; then
    fatal "The destination path \"${DSTPATH}\" is not writable for this user"
fi

# Check for existing lockfile to avoid multiple simultaneously running syncs
# If lockfile exists but process is dead continue anyway
if [ -e "$LOCKFILE" ] && [ ! kill -0 "$(< "$LOCKFILE")" 2>/dev/null ]; then
    warning "lockfile exists but process dead, continuing..."
    rm -f "$LOCKFILE"
elif [ -e "$LOCKFILE" ]; then
    info "A update is already in progress, exiting..."
    exit 1
fi

# Main script functions
print_header_updatelog() {
    # Expected command:
    # print_header_updatelog "rsync" "$SRC" "$DST" "$TRANSFERSIZE" "$AVAILABLESIZE" "$UPDATELOGFILE" "${OPTS[*]}"
    
    # Get script version
    VERSION=$(cat ${SCRIPTDIR}/.version)

    # Print info to new updatelog
    printf "# Syncronization with %s using Mirrorsync by CodeOOf\n" "$1" >> "$6" 2>&1
    printf "# Version: %s\n" "$VERSION" >> "$6" 2>&1
    printf "# Date: %(%Y-%m-%d %H:%M:%s)T\n" -1 >> "$6" 2>&1
    printf "# \n" >> "$6" 2>&1
    printf "# Source: %s\n" "$2" >> "$6" 2>&1
    printf "# Destination: %s\n" "$3" >> "$6" 2>&1
    printf "# Using the following %s options for this run:\n" "$1" >> "$6" 2>&1
    printf "#   %s\n" "$7" >> "$6" 2>&1
    printf "# This transfer will use: %i of %i current available.\n" "$4" "$5" >> "$6" 2>&1
    printf "---\n" >> "$6" 2>&1
    printf "Files transfered: \n\n" >> "$6" 2>&1
}

# Main script
printf '%s\n' "$$" > "$LOCKFILE"

# Start updating each mirror repo
info "Synchronization process starting..."

for FILE in "${REPOCONFIGS[@]}"
do
    printf "[%(%F %T)T] Info: Now working on repository defined at: %s\n" -1 "$FILE" >> "$LOGFILE" 2>&1

    LOCALDIR=""
    FILELISTFILE=""
    EXCLUDELIST=()
    MINMAJOR=0
    MINMINOR=0
    REMOTES=()
    SRC=""
    PORT=0

    source $FILE

    # Define the new path
    DST="${DSTPATH}/$LOCALDIR"

    # Validate local path is defined and able to write to
    if [ -z "$LOCALDIR" ]; then
        error "no local directory is defined in \"${FILE}\", cannot update this mirror continuing with the next"
        continue
    elif [ ! -w "$DST" ]; then
        error "The path \"${DST}\" is not writable, cannot update this mirror continuing with the next"
        continue
    elif [ ! -d "$DST" ]; then
        warning "A local path for \"${LOCALDIR}\" does not exists, will create one"
        if [ ! mkdir "$DST" 2>/dev/null ]; then
            error "The path \"${DST}\" could not be created, cannot update this mirror continuing with the next"
            continue
        fi
    fi
    
    # Validate the remotes variable is a array
    if [ ! $(declare -p REMOTES | grep '^declare -a') ]; then
        error "The remotes defined for \"${LOCALDIR}\" is invalid, cannot update this mirror continuing with the next"
        continue
    fi
    
    # Verify network connectivity against the remote and the select first available
    for REMOTE in "${REMOTES[@]}"
    do
        # Check the protocol defined in the begining of the url and map it against a port number
        case "${REMOTE%%:*}" in
            rsync)
                PORT=$RSYNC_PORT
                ;;
            https)
                PORT=$HTTPS_PORT
                ;;
            http)
                PORT=$HTTP_PORT
                ;;
            *)
                error "The remote path \"${REMOTE}\" contains a invalid protocol"
                continue
                ;;
        esac
        
        # Make a connection test against the url on that port to validate connectivity
        DOMAIN=$(echo $REMOTE | awk -F[/:] '{print $4}')
        (echo > /dev/tcp/${DOMAIN}/${PORT}) &>/dev/null
        if [ $? -eq 0 ]; then
            info "Connection valid for \"${REMOTE}\", continuing..."
            SRC=$REMOTE
            break
        fi

        # If we get here the connection did not work
        warning "No connection with \"${REMOTE}\", testing the next remote..."
    done

    # If no source url is defined it means we did not find a valid remote url that we can connect to now
    if [ -z "$SRC" ]; then
        error "No connection with any remote found in \"${FILE}\", cannot update this mirror continuing with the next"
        continue
    fi

    # Many mirrors provide a filelist that is much faster to validate against first and takes less requests, 
    # So we start with that
    CHECKRESULT=""
    if [ -z "$FILELISTFILE" ]; then
        info "The variable \"FILELISTFILE\" is empty or not defined at \"${FILE}\", continuing..."
    elif [ "$PORT" == "$RSYNC_PORT" ]; then
        CHECKRESULT=$(rsync --no-motd --dry-run --out-format="%n" "${SRC}/$FILELISTFILE" "${DST}/$FILELISTFILE")
    else
        warning "The protocol used with \"${SRC}\" has not yet been implemented. Move another protocol higher up in 
list of remotes to solve this at the moment. Cannot update this mirror continuing with the next"
        continue
    fi

    # Check the results of the filelist against the local
    if [ -z "$CHECKRESULT" ] && [ ! -z "$FILELISTFILE" ]; then
        info "The filelist is unchanged at \"${SRC}\", no update required for this mirror continuing with the next"
        continue
    fi

    # Create a new exlude file before running the update
    EXCLUDEFILE="${SCRIPTDIR}/${LOCALDIR}_exclude.txt"
    # Clear file
    > $EXCLUDEFILE

    # Validate the exclude list variable is a array
    if [ ! $(declare -p EXCLUDELIST | grep '^declare -a') ]; then
        error "The exclude list defined for \"${LOCALDIR}\" is invalid, will ignore it and continue."
        EXCLUDELIST=()
    fi

    # Generate the version exclude list, assumes that the versions are organized at root
    if [ "$MINMAJOR" > 0 ]; then
        for i in $(seq 0 $((MINMAJOR -1)))
        do
            EXCLUDELIST+=("/$i" "$i.*")
        done
        if [ "$MINMINOR" > 0 ]; then
            for i in $(seq 0 $((MINMINOR -1)))
            do
                EXCLUDELIST+=("/$MINMAJOR.$i")
            done
        fi
    fi

    # Write the new excludes into the excludefile
    for EXCLUDE in "${EXCLUDELIST[@]}"
    do
        printf "$EXCLUDE\n" >> $EXCLUDEFILE
    done

    # Depending on what protocol the url has the approch on syncronizing the repo is different
    case "$PORT" in
        "$RSYNC_PORT")
            # Set variables for the run
            OPTS=(-vrlptDSH --delete-excluded --delete-delay --delay-updates --exclude-from=$EXCLUDEFILE)
            UPDATELOGFILE="${LOGPATH}/$(date +%y%m%d%H%M)_${LOCALDIR}_rsyncupdate.log"

            # First validate that there is enough space on the disk
            TRANSFERBYTES=$(rsync "${OPTS[@]}" --dry-run --stats "${SRC}/" "${DST}/" | grep "Total transferred" \
            | sed 's/[^0-9]*//g')
            AVAILABLEBYTES=$(df -B1 $DST | awk 'NR>1{print $4}')

            # Convert bytes into human readable
            TRANSFERSIZE=$($4 | numfmt --to=iec-i)
            AVAILABLESIZE=$($5 | numfmt --to=iec-i)
                
            if [ "$TRANSFERBYTES" > "$AVAILABLEBYTES" ]; then
                error "Not enough space on disk! This transfer needs $TRANSFERSIZE of $AVAILABLESIZE available. Cannot 
update this mirror continuing with the next"
                continue
            fi

            # Header for the new log fil
            print_header_updatelog "rsync" "$SRC" "$DST" "$TRANSFERSIZE" "$AVAILABLESIZE" "$UPDATELOGFILE" "${OPTS[*]}"

            # Start updating
            rsync "${opts[@]}" "${SRC}/" "${DST}/" >> "$UPDATELOGFILE" 2>&1

            # Finished
            info "Finished updating mirror \"${LOCALDIR}\", log found at \"${UPDATELOGFILE}\""
            ;;
        *)
            warning "The protocol defined for \"${SRC}\" is invalid, cannot update this mirror continuing with the next"
            ;;
    esac
done

# Finished
info "Synchronization process finished"
rm -f "$LOCKFILE"

exit 0