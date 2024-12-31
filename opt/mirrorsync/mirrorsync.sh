#!/bin/env bash
# 
# Mirrorsync - mirrorsync.sh
# Author: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

# Global Variables
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
CONFIGDIR="/etc/mirrorsync"
EXCLUDESDIR="${SCRIPTDIR}/excludes"
LOGFILE=""
VERBOSE=""
HTTP_PORT=80
HTTPS_PORT=443
RSYNC_PORT=873
TIMEOUT=2
STDOUT=0
VERBOSE_ARG=0
DEBUG_ARG=0
SHOW_PROGRESS=0
BARLENGTH=40
INTEGERCHECK='^[0-9]+$'

# Log functions for standard output
log_stdout() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }
info_stdout() { log_stdout "$*" >&2; }
debug_stdout() { log_stdout "Debug: $*" >&2; }
warning_stdout() { log_stdout "Warning: $*" >&2; }
error_stdout() { log_stdout "Error: $*" >&2; }
fatal_stdout() { error_stdout "$*, exiting..."; exit 1; }
error_argument() { error_stdout "$*, exiting..."; usage >&2; exit 1; }

# Log functions
log() { 
    printf "[%(%F %T)T] %s\n" -1 "$*" >> "$LOGFILE" 2>&1
    if [ $STDOUT -eq 1 ] || [ $VERBOSE_ARG -eq 1 ]; then log_stdout "$*" >&2; fi
}

info() { 
    if [ ! -z "$VERBOSE" ] && [ $VERBOSE -eq 1 ]; then log "$*" >&2; fi
    if [ $VERBOSE_ARG -eq 1 ]; then log_stdout "$*" >&2; fi
}

debug() { if [ $DEBUG_ARG -eq 1 ]; then debug_stdout "$*" >&2; fi }
warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { error "$*, exiting..."; exit 1; }

# Usage: progress <current count> <total count>
# ex. progress 1 5
progress() {
    local count=$1
    local total=$2
    local progress=0

    # Calculate current state
    if [ $count -gt 0 ]; then progress=$(((count*100)/total)); fi
    local donecount=$(((count*BARLENGTH)/total))
    local leftcount=$((BARLENGTH-donecount))

    debug "Current progress counter ${count}/${total}: ${progress}%"
    debug "Progress fill is [${donecount}-${leftcount}]"

    # Create the printf parts
    local donefill=$(printf "%${donecount}s")
    local leftfill=$(printf "%${leftcount}s")

    # Only show the progressbar if we know the stdout is empty
    if [ $SHOW_PROGRESS -eq 1 ]; then
        if [ $VERBOSE_ARG -eq 1 ] || [ $DEBUG_ARG -eq 1 ]; then
            # If debug or verbose activated display it in text format
            log_stdout "Progress: [${donefill// /#}${leftfill// /-}] ${progress}%%\n"
        elif [ ! -z "$VERBOSE" ] && [ $VERBOSE -eq 1 ]; then
            # Verbose will print progress to logfile
            log "Progress: [${donefill// /#}${leftfill// /-}] ${progress}%%\n"
        else
            # Display the dynamic progressbar
            # Only works if no other printouts to standard output is made
            printf "\rProgress: [${donefill// /#}${leftfill// /-}] ${progress}%%"
            if [ $leftcount -eq 0 ]; then printf "\n"; fi
        fi
    fi
}

# Arguments Help
usage() {
    cat << EOF
Usage: $0 [options]

Arguments:

  -h, --help
    Display this usage message and exit.

  --config-path=PATH
    Set a path from where this script can read the configurations and settings.
    Default: $CONFIGDIR

  -d, --debug
    Activate Debug Mode, provides a very detailed output to the system console.

  --excludes-path=PATH
    Set a path from where this script can read and write files with exlude patterns listed.
    Default: $EXCLUDESDIR

  -p, --progress
    Display a progress bar to standard output.

  -s, --stdout
    Activate Standard Output, streams every output to the system console.

  -v, --verbose
    Activate Verbose Mode, provides more a more detailed output to the system console.
EOF
}

# Arguments Parser
while [ "$#" -gt 0 ]; do
    case $1 in
        --config-path=*) EXCLUDESDIR="${1#*=}";;
        -d|--debug) DEBUG_ARG=1;;
        --excludes-path=*) EXCLUDESDIR="${1#*=}";;
        -h|--help) usage; exit 0;;
        -p|--progress) SHOW_PROGRESS=1;;
        -s|--stdout) STDOUT=1;;
        -v|--verbose) VERBOSE_ARG=1;;
        --) shift; break;;
        -*) error_argument "Unknown option: '$1'";;
        *) break;;
    esac
    shift || error_argument "Option '${1}' requires a value"
done

# Updated variables after arguments parser
CONFIGFILE="${CONFIGDIR}/mirrorsync.conf"
REPOCONFIGDIR="${CONFIGDIR}/repos.conf.d"
LOCKFILE="${EXCLUDESDIR}/mirrorsync.sh.lockfile"

# Verify config file is readable
if [ ! -r "$CONFIGFILE" ]; then
    fatal_stdout "The script configfile \"$CONFIGFILE\" is not availble or readable"
else
    source "$CONFIGFILE"
fi

# Verify repo path exists
if [ ! -d "$REPOCONFIGDIR" ]; then
    fatal_stdout "The directory \"$REPOCONFIGDIR\" does not exist"
fi

# Verify that there are any mirror repositories to work with
REPOCONFIGS=(${REPOCONFIGDIR}/*.conf)
# Remove example config from list
for index in "${!REPOCONFIGS[@]}"
do
    if [ "${REPOCONFIGS[$index]}" == "${REPOCONFIGDIR}/example.conf" ]; then
        unset REPOCONFIGS[$index]
    fi
done
# Verify that there are items left
if [ ${#REPOCONFIGS[@]} -eq 0 ]; then
    fatal_stdout "The directory \"$REPOCONFIGDIR\" is empty or contains no config files, please provide repository " \
    "config files that this script can work with"
fi

# Progress counter data
progresscounter=0
REPOSTOTAL=${#REPOCONFIGS[@]}
PROGRESSTOTAL=$((REPOSTOTAL*3+1))

# Verify that current path is writable
if [ ! -w "$SCRIPTDIR" ]; then
    fatal_stdout "The directory where this script is located is not writable for this user. This is required for the " \
    "lockfile to avoid multiple simultaneous runs of the script"
fi
if [ ! -w "$EXCLUDESDIR" ]; then
    fatal_stdout "The directory \"${EXCLUDESDIR}\" is not writable for this user. This is required for the exclude " \
    "files"
fi
VERSION=$(cat ${SCRIPTDIR}/.version)
HTTPSYNC="${SCRIPTDIR}/httpsync.sh"

# Validate current settings
if [ -z "$LOGPATH" ]; then 
    info_stdout "Missing variable \"LOGPATH\" at \"$CONFIGFILE\", using default"
    LOGPATH="/var/log/mirrorsync"
fi

if [ ! -w "$LOGPATH" ]; then
    fatal_stdout "The log directory is not writable for this user: $LOGPATH"
fi

if [ -z "$LOGFILENAME" ]; then 
    info_stdout "Missing variable \"LOGFILENAME\" at \"$CONFIGFILE\", using default"
    LOGFILENAME="$0"
fi
LOGFILE="${LOGPATH}/${LOGFILENAME}.log"

if [ -z "$LOCALDST" ]; then 
    fatal "Missing variable \"LOCALDST\" at \"${CONFIGFILE}\". It is required to know where to write the mirror data"
fi

if [ ! -w "$LOCALDST" ]; then
    fatal "The destination path \"${LOCALDST}\" is not writable for this user"
fi

# Check for existing lockfile to avoid multiple simultaneously running syncs
# If lockfile exists but process is dead continue anyway
if [ -e "$LOCKFILE" ] && ! kill -0 "$(< "$LOCKFILE")" 2>/dev/null; then
    warning "lockfile exists but process dead, continuing"
    rm -f "$LOCKFILE"
elif [ -e "$LOCKFILE" ]; then
    info "A update is already in progress, exiting"
    exit 1
fi

# Main script functions
print_header_updatelog() {
    # Expected command:
    # print_header_updatelog "rsync" "$SRC" "$DST" "$TRANSFERSIZE" "$AVAILABLESIZE" "$UPDATELOGFILE" "${OPTS[*]}"
    local headerbar=$(printf "%${BARLENGTH}s")
    
    # Print info to new updatelog
    printf "# Syncronization with Mirrorsync by CodeOOf via %s\n" "$1" >> "$6" 2>&1
    printf "# Version: %s\n" "$VERSION" >> "$6" 2>&1
    printf "# Date: %(%Y-%m-%d %H:%M:%S)T\n" -1 >> "$6" 2>&1
    printf "# \n" >> "$6" 2>&1
    printf "# Source: %s\n" "$2" >> "$6" 2>&1
    printf "# Destination: %s\n" "$3" >> "$6" 2>&1
    printf "# Using the following options will be used for this run:\n" >> "$6" 2>&1
    printf "#   %s\n" "$7" >> "$6" 2>&1
    printf "# This transfer will use: %sB of %sB current available.\n" "$4" "$5" >> "$6" 2>&1
    printf "# ${headerbar// /-}\n\n" >> "$6" 2>&1
    printf "Files transfered: \n\n" >> "$6" 2>&1
}


# Main script
printf '%s\n' "$$" > "$LOCKFILE"

# Start updating each mirror repo
log "Synchronization process starting..."

# Initial validation phase done now starts the sync
progress "$progresscounter" "$PROGRESSTOTAL"

for repoconfig in "${REPOCONFIGS[@]}"
do
    log "Starting to synchronize mirror defined at \"$repoconfig\""

    mirrorname=""
    filelistfile=""
    excludequeries=()
    minmajor=0
    minminor=0
    remotes=()
    remotesrc=""
    remoteport=0

    # First verify that file is readable
    if [ ! -r "$repoconfig" ]; then
        error "The repository configuration file \"${repoconfig}\" is not readable. Continuing with the next mirror"
        progresscounter=$((progresscounter+3))
        continue
    else
        # Load configuration
        source $repoconfig
    fi

    # Define the new path
    mirrordst="${LOCALDST}/$mirrorname"

    # Validate local path is defined and able to write to
    if [ -z "$mirrorname" ]; then
        error "no local directory is defined in \"${repoconfig}\". Continuing with the next mirror"
        progresscounter=$((progresscounter+3))
        continue
    fi

    # Check if directory exists, else create it
    if [ ! -d "$mirrordst" ]; then
        warning "A local path for \"${mirrorname}\" does not exists, will create one"
        if [ ! mkdir "$mirrordst" 2>&1 ]; then
            error "The path \"${mirrordst}\" could not be created. Continuing with the next mirror"
            progresscounter=$((progresscounter+3))
            continue
        fi
    fi

    # Validate that the current user can write to this path
    if [ ! -w "$mirrordst" ]; then
        error "The path \"${mirrordst}\" is not writable. Continuing with the next mirror"
        progresscounter=$((progresscounter+3))
        continue
    fi
    
    # Validate the remotes variable is a array
    is_array=$(declare -p remotes | grep '^declare -a')
    if [ -z "$is_array" ]; then
        error "The remotes defined for \"${mirrorname}\" is invalid. Continuing with the next mirror"
        progresscounter=$((progresscounter+3))
        continue
    fi
    
    # Verify network connectivity against the remote and the select first available
    for remote in "${remotes[@]}"
    do
        debug "Start validating remote entry \"${remote}\""
        # Check the protocol defined in the begining of the url and map it against a port number
        case "${remote%%:*}" in
            rsync)
                debug "Connection against this remote is done via \"rsync\" port: $RSYNC_PORT"
                remoteport=$RSYNC_PORT
                ;;
            https)
                debug "Connection against this remote is done via \"https\" port: $HTTPS_PORT"
                remoteport=$HTTPS_PORT
                ;;
            http)
                debug "Connection against this remote is done via \"http\" port: $HTTP_PORT"
                remoteport=$HTTP_PORT
                ;;
            *)
                error "The remote \"${remote}\" contains a protocol not yet implemented"
                continue
                ;;
        esac

        if [ -z "$remoteport" ]; then
            error "Could not extract port number for the remote \"${remote}\""
            continue
        fi
        
        # Make a connection test against the url on that port to validate connectivity
        domain=$(echo $remote | awk -F[/:] '{print $4}' | sed -z 's/[[:space:]]*$//')
        tcp_str="/dev/tcp/${domain}/${remoteport}"
        debug "Connection test string to be used: $tcp_str"
        timeout $TIMEOUT bash -c "<$tcp_str" 2>/dev/null
        
        test_response=$?
        debug "Test response code from connection test: $test_response"
        if [ $test_response -eq 0 ]; then
            log "The mirror \"${mirrorname}\" will synchronize with \"${remote}\""
            remotesrc=$remote
            break
        fi

        # If we get here the connection did not work
        warning "No connection with \"${remote}\", testing the next remote..."
    done

    # If no source url is defined it means we did not find a valid remote url that we can connect to now
    if [ -z "$remotesrc" ]; then
        error "No connection with any remote found in \"${repoconfig}\". Continuing with the next mirror"
        progresscounter=$((progresscounter+3))
        continue
    fi

    # Mirror sync phase 1 complete
    # Extract a remote to work with
    ((++progresscounter))
    progress "$progresscounter" "$PROGRESSTOTAL"

    # Many mirrors provide a filelist that is much faster to validate against first and takes less requests, 
    # So we start with that
    checkresult=""
    if [ -z "$filelistfile" ]; then
        info "The variable \"filelistfile\" is empty or not defined for \"${repoconfig}\""
    elif [ "$remoteport" == "$RSYNC_PORT" ]; then
        checkresult=$(rsync --no-motd --dry-run --out-format="%n" "${remotesrc}/$filelistfile" \
        "${mirrordst}/$filelistfile")
    else
        info "The protocol used with \"${remotesrc}\" has not yet implemented for filelist file checks"
        checkresult="?"
    fi

    # Check the results of the filelist against the local
    if [ ! -z "$filelistfile" ] && [ -z "$checkresult" ]; then
        log "The filelist is unchanged at \"${remotesrc}\", no update required. Continuing with the next mirror"
        progresscounter=$((progresscounter+2))
        continue
    fi

    # Create a new exlude file before running the update
    excludefile="${EXCLUDESDIR}/${mirrorname}_exclude.txt"
    # Clear file
    > $excludefile

    # Validate the exclude list variable is a array
    if [ ! $(declare -p excludequeries | grep '^declare -a') ]; then
        error "The exclude list defined for \"${mirrorname}\" is invalid, will ignore it and continue."
        excludequeries=()
    fi

    # Generate the version exclude list, assumes that the versions are organized at root
    debug "Current exclude versions is up to v${minmajor}.${minminor}"
    if [ $minmajor -gt 0 ]; then
        for i in $(seq 0 $((minmajor -1)))
        do
            excludequeries+=("/$i" "/$i.*")
        done
        if [ $minminor -gt 0 ]; then
            for i in $(seq 0 $((minminor -1)))
            do
                excludequeries+=("/$minmajor.$i")
            done
        fi
    fi
    debug "Current generated excludequeries is: ${excludequeries[*]}"

    # Write the new excludes into the excludefile
    for exclude in "${excludequeries[@]}"
    do
        printf "%s\n" "${exclude}" >> $excludefile 2>&1
    done
    debug "excludes added to the file \"${excludefile}\""

    # Current disk spaces in bytes
    availablebytes=$(df -B1 $mirrordst | awk 'NR>1{print $4}' | tr -cd '[:digit:].')
    availablesize=$(echo $availablebytes | numfmt --to=iec-i)
    repobytes=$(du -sB1 "${mirrordst}/" | awk 'NR>0{print $1}' | tr -cd '[:digit:].')

    # Mirror sync phase 2 complete
    # Construct exludelists
    ((++progresscounter))
    progress "$progresscounter" "$PROGRESSTOTAL"

    # Depending on what protocol the url has the approch on syncronizing the repo is different
    case $remoteport in
        $RSYNC_PORT)
            # Set variables for the run
            opts=(-vrlptDSH --delete-excluded --delete-delay --delay-updates --exclude-from=$excludefile)
            updatelogfile="${LOGPATH}/$(date +%y%m%d%H%M)_${mirrorname}_rsyncupdate.log"

            # First validate that there is enough space on the disk
            debug "Command used to receive transfer size: rsync ${opts[@]} --dry-run --stats ${remotesrc}/ " \
            "${mirrordst}/ | grep -i \"Total transferred\" | sed 's/[^0-9]*//g')"
            transferbytes=$(rsync "${opts[@]}" --dry-run --stats "${remotesrc}/" "${mirrordst}/" | \
            grep -i "Total transferred" | sed 's/[^0-9]*//g')
            debug "The transfer will take \"${transferbytes}B\""

            # Validate that the recived size is a number and anything
            if ! [[ $transferbytes =~ $INTEGERCHECK ]]; then
                error "Did not receive correct data from rsync. Continuing with the next mirror"
                ((++progresscounter))
                continue
            elif [ $transferbytes -eq 0 ]; then 
                info "There is nothing to update for \"${mirrorname}\". Continuing with the next mirror"
                ((++progresscounter))
                continue
            fi

            transfersize=$(echo $transferbytes | numfmt --to=iec-i)
            info "This synchronization will require ${transfersize}B on local storage"
                
            if [ $transferbytes -gt $availablebytes ]; then
                error "Not enough space on disk! This transfer needs ${transfersize}B of ${availablesize}B " \
                "available. Continuing with the next mirror"
                ((++progresscounter))
                continue
            fi

            # header for the new log fil
            print_header_updatelog "rsync" "$remotesrc" "$mirrordst" "$transfersize" "$availablesize" "$updatelogfile" \
            "${opts[*]}"

            # Start updating
            debug "Command used to syncronize mirror: $HTTPSYNC ${opts[@]} ${remotesrc}/ ${mirrordst}/"
            rsync "${opts[@]}" "${remotesrc}/" "${mirrordst}/" >> "$updatelogfile" 2>&1

            # Finished
            log "Finished updating mirror \"${mirrorname}\", log found at \"${updatelogfile}\""
            ;;
        $HTTP_PORT|$HTTPS_PORT)
            # Set variables for the run
            opts=(-r --delete-excluded --exclude-from=$excludefile)
            updatelogfile="${LOGPATH}/$(date +%y%m%d%H%M)_${mirrorname}_httpupdate.log"

            # First validate that there is enough space on the disk
            debug "Command used to receive transfer size: $HTTPSYNC ${opts[@]} --stats ${remotesrc}/ ${mirrordst}/"
            transferbytes=$($HTTPSYNC "${opts[@]}" --stats "${remotesrc}/" "${mirrordst}/" 2>&1)
            debug "The transfer will take \"${transferbytes}B\""

            # Validate that the recived size is a number and anything
            if ! [[ $transferbytes =~ $INTEGERCHECK ]]; then
                error "Did not receive correct data from httpsync. Continuing with the next mirror"
                ((++progresscounter))
                continue
            elif [ $transferbytes -eq 0 ]; then 
                info "There is nothing to update for \"${mirrorname}\". Continuing with the next mirror"
                ((++progresscounter))
                continue
            fi

            # If we have debug or verbose activated at the main script, follow using it at httpsync
            if [ $DEBUG_ARG -eq 1 ]; then opts+=(-d); fi
            if [ $VERBOSE_ARG -eq 1 ]; then opts+=(-v); fi

            transfersize=$(echo $transferbytes | numfmt --to=iec-i)
            info "This synchronization will require ${transfersize}B on local storage"
                
            if [ $transferbytes -gt $availablebytes ]; then
                error "Not enough space on disk! This transfer needs ${transfersize}B of ${availablesize}B " \
                "available. Continuing with the next mirror"
                ((++progresscounter))
                continue
            fi

            # header for the new log fil
            print_header_updatelog "http" "$remotesrc" "$mirrordst" "$transfersize" "$availablesize" "$updatelogfile" \
            "${opts[*]}"

            # Start updating
            debug "Command used to syncronize mirror: $HTTPSYNC ${opts[@]} ${remotesrc}/ ${mirrordst}/"
            $HTTPSYNC "${opts[@]}" "${remotesrc}/" "${mirrordst}/" >> "$updatelogfile" 2>&1

            # Finished
            log "Finished updating mirror \"${mirrorname}\", log found at \"${updatelogfile}\""
            ;;
        *)
            warning "The protocol defined for \"${remotesrc}\" is invalid. Continuing with the next mirror"
            ;;
    esac

    # Mirror sync phase 3 complete
    # Finished syncing
    ((++progresscounter))
    progress "$progresscounter" "$PROGRESSTOTAL"
done

# Finished
((++progresscounter))
progress "$progresscounter" "$PROGRESSTOTAL"

# Finished
log "Synchronization process finished"
rm -f "$LOCKFILE"

exit 0