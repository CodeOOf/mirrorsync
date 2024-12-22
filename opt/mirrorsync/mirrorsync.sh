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
CONFIGFILE="/etc/mirrorsync/mirrorsync.conf"
REPOCONFIGDIR="/etc/mirrorsync/repos.conf.d"
LOCKFILE="$0.lockfile"
LOGFILE=""
VERBOSE=""
HTTP_PORT=80
HTTPS_PORT=443
RSYNC_PORT=873
STDOUT=0
VERBOSE_ARG=0
DEBUG_ARG=0

# Log functions for standard output
log_stdout() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }
info_stdout() { log_stdout "$*" >&2; }
debug_stdout() { log_stdout "Debug: $*" >&2; }
warning_stdout() { log_stdout "Warning: $*" >&2; }
error_stdout() { log_stdout "Error: $*" >&2; }
fatal_stdout() { error_stdout "$*, exiting..."; exit 1; }
argerror_stdout() { error_stdout "$*, exiting..."; usage >&2; exit 1; }

# Log functions
log() { 
    printf "[%(%F %T)T] %s\n" -1 "$*" >> "$LOGFILE" 2>&1
    if [ $STDOUT -eq 1 ] || [ $VERBOSE_ARG -eq 1 ]; then log_stdout "$*" >&2; fi
}

info() { 
    if [ ! -z "$VERBOSE" ] && [ $VERBOSE -eq 1 ]; then log "$*" >&2; fi
    if [ $VERBOSE_ARG -eq 1 ]; then log_stdout "$*" >&2; fi
}

debug() { 
    if [ $DEBUG_ARG -eq 1 ]; then debug_stdout "$*" >&2; fi
}

warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { error "$*, exiting..."; exit 1; }

# Arguments Help
usage() {
    cat << EOF
Usage: $0 [options]

Arguments:

  -h, --help
    Display this usage message and exit.

  -d, --debug
    Activate Debug Mode, provides a very detailed output to the system console.

  -s, --stdout
    Activate Standard Output, streams every output to the system console.

  -v, --verbose
    Activate Verbose Mode, provides more a more detailed output to the system console.
EOF
}

# Arguments Parser
while [ "$#" -gt 0 ]; do
    arg=$1
    case $1 in
        # Convert "--opt=value" to --opt "value"
        --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
        -d|--debug) DEBUG_ARG=1; info_stdout "Debug Mode Activated";;
        -s|--stdout) STDOUT=1; info_stdout "Standard Output Activated";;
        -v|--verbose) VERBOSE_ARG=1; info_stdout "Verbose Mode Activated";;
        -h|--help) usage; exit 0;;
        --) shift; break;;
        -*) argerror_stdout "Unknown option: '$1'";;
        *) break;;
    esac
    shift || argerror_stdout "Option '${arg}' requires a value"
done

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
    if [ "${REPOCONFIGS[$index]}" == "example.conf" ]; then
        unset REPOCONFIGS[$index]
    fi
done
# Verify that there are items left
if [ ${#REPOCONFIGS[@]} -eq 0 ]; then
    fatal_stdout "The directory \"$REPOCONFIGDIR\" is empty or contains no config files, please provide repository 
config files that this script can work with"
fi

# Verify that current path is writable
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
if [ ! -w "$SCRIPTDIR" ]; then
    fatal_stdout "The directory where this script is located is not writable for this user. This is required for the 
lockfile to avoid multiple simultaneous runs of the script"
fi
VERSION=$(cat ${SCRIPTDIR}/.version)

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
if [ -e "$LOCKFILE" ] && ! kill -0 "$(< "$LOCKFILE")" 2>&1; then
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
    
    # Print info to new updatelog
    printf "# Syncronization with %s using Mirrorsync by CodeOOf\n" "$1" >> "$6" 2>&1
    printf "# Version: %s\n" "$VERSION" >> "$6" 2>&1
    printf "# Date: %(%Y-%m-%d %H:%M:%s)T\n" -1 >> "$6" 2>&1
    printf "# \n" >> "$6" 2>&1
    printf "# Source: %s\n" "$2" >> "$6" 2>&1
    printf "# Destination: %s\n" "$3" >> "$6" 2>&1
    printf "# Using the following %s options for this run:\n" "$1" >> "$6" 2>&1
    printf "#   %s\n" "$7" >> "$6" 2>&1
    printf "# This transfer will use: %sB of %sB current available.\n" "$4" "$5" >> "$6" 2>&1
    printf "---\n" >> "$6" 2>&1
    printf "Files transfered: \n\n" >> "$6" 2>&1
}

# Function to validate if value is matched in a array of queries
# Usage: arraymatch "value_to_test" "array of values to validate"
arraymatch() {
    local queries=($2)
    local value="$1"

    if [ "${1:-1:1}" == "/" ]; then value=${1:0:-1}; fi

    for query in "${queries[@]}"
    do
        if [[ "$value" == $query ]] || [[ "${1:0:-1}" == $query ]]; then 
            debug "The value \"${1}\" matched query \"${query}\""; 
            return 0; 
        fi
    done

    return 1
}

# This is a recursive function that will parse through a website with listed items and compare with local
# returning a list of itemes out of sync
# Usage: httpsync "http://example.com/pub/repo/" "/my/local/destination/" "(EXCLUDE/,*FILES,and~,/dirs)"
# With the ending slash on paths and urls
# excludes starting with "/" only excludes from root
httpsync() {
    local filelist=()
    local baseurl=$1
    local localpath=$2
    local querylist=($3)
    local rootqueries=()

    # Extract all root items to exlude
    for index in "${!querylist[@]}"
    do
        if [ "${querylist[$index]:0:1}" == "/" ]; then
            rootqueries+=("${querylist[$index]:1}")
            unset querylist[$index]
        fi
    done
    debug "Queries used only for \"${baseurl}\": ${rootqueries[*]}"

    # Get all the links on that page
    debug "Begin scraping paths from \"$baseurl\""
    for href in $(curl -s "$baseurl" | sed -n "/href/ s/.*href=['\"]\([^'\"]*\)['\"].*/\1/gp")
    do 
        debug "Now working on relative path: $href"
        # Constructs the new url, assuming relative paths at remote
        local url="${baseurl}$href"
        local dst="${localpath}$href"

        # Check if part of exclude list
        if (arraymatch "$href" "${querylist[*]}") || (arraymatch "$href" "${rootqueries[*]}"); then
            debug "The path \"${href}\" is part of the exclude"
            continue
        fi

        # Check if the href ends with slash and not parent or begins with slash
        if [ "${#href}" -gt 1 ] && [ "${href: -1:1}" == $'/' ]  && 
        [ "${href: -2:2}" != $"./" ] && [ "${href: 0:1}" != $'/' ]; then
            # Call recursivly until no more directories are found
            local recursivecall=$(httpsync "$url" "$dst" "${querylist[*]}" | tr -d '\0')

            # Only add to collection if array is populated
            local is_array=$(declare -p recursivecall | grep '^declare -a')
            if [ -z "$is_array" ]; then
                filelist+=$recursivecall
            fi
        # As long as it is not ending slash, assume as file
        elif [ "${href: -1:1}" != $'/' ]; then
            local bytes=""
            local modified=""
            # Verify that url exists
            if curl -ivs "$url" 2>&1; then
                # Extract content information from header response
                local header=$(curl -sI "$url")

                # Check if location exists first so that we extract information from the file source
                local location=$(echo "${header[*]}" | grep -i "location" | awk '{print $2}' \
                | sed -z 's/[[:space:]]*$//')
                if [ ! -z "$location" ]; then
                    info "Found file at another domain \"${location}\" for \"${dst}\""
                    header=$(curl -sI "$location")
                    url=$location
                fi

                # Extract file information
                bytes=$(echo "${header[*]}" | grep -i "Content-Length" | awk '{print $2}' | tr -cd '[:digit:].')
                local modified_STR=$(echo "${header[*]}" | grep -i "Last-modified" \
                | awk -v 'IGNORECASE=1' -F'Last-modified:' '{print $2}')
                modified=$(date -d "$modified_STR" "+%Y-%m-%d %H:%M:%S")

                if [ ! -z "$bytes" ] && [ $bytes -gt 0 ]; then
                    # TODO: Check if local file is out of sync with this.

                    filesize=$(echo $bytes | numfmt --to=iec-i)
                    debug "Added a file of size ${filesize}B from \"${url}\" to the list, it was last modifed 
\"${modified}\""
                    # Add to the array
                    local file=("$url" "$modified" "$bytes" "$dst")
                    filelist+=($file)
                else
                    debug "Not a file \"$url\", ignoring path"
                fi
            else
                info "Invalid url constructed at remote: $url"
            fi
        else
            debug "Ignoring parent path \"${href}\" at remote: $baseurl"
        fi
    done
    echo "${filelist[*]}"
}

# Main script
printf '%s\n' "$$" > "$LOCKFILE"

# Start updating each mirror repo
log "Synchronization process starting..."

for repoconfig in "${REPOCONFIGS[@]}"
do
    info "Now working on repository defined at: $repoconfig"

    mirrorname=""
    filelistfile=""
    excludequeries=()
    minmajor=0
    minminor=0
    remotes=()
    remotesrc=""
    port=0

    source $repoconfig

    # Define the new path
    mirrordst="${LOCALDST}/$mirrorname"

    # Validate local path is defined and able to write to
    if [ -z "$mirrorname" ]; then
        error "no local directory is defined in \"${repoconfig}\", cannot update this mirror continuing with the next"
        continue
    elif [ ! -w "$mirrordst" ]; then
        error "The path \"${mirrordst}\" is not writable, cannot update this mirror continuing with the next"
        continue
    elif [ ! -d "$mirrordst" ]; then
        warning "A local path for \"${mirrorname}\" does not exists, will create one"
        if [ ! mkdir "$mirrordst" 2>&1 ]; then
            error "The path \"${mirrordst}\" could not be created, cannot update this mirror continuing with the next"
            continue
        fi
    fi
    
    # Validate the remotes variable is a array
    is_array=$(declare -p remotes | grep '^declare -a')
    if [ -z "$is_array" ]; then
        error "The remotes defined for \"${mirrorname}\" is invalid, cannot update this mirror continuing with the next"
        continue
    fi
    
    # Verify network connectivity against the remote and the select first available
    for remote in "${remotes[@]}"
    do
        # Check the protocol defined in the begining of the url and map it against a port number
        case "${remote%%:*}" in
            rsync)
                port=$RSYNC_port
                ;;
            https)
                port=$HTTPS_port
                ;;
            http)
                port=$HTTP_port
                ;;
            *)
                error "The remote path \"${remote}\" contains a invalid protocol"
                continue
                ;;
        esac
        
        # Make a connection test against the url on that port to validate connectivity
        domain=$(echo $remote | awk -F[/:] '{print $4}' | sed -z 's/[[:space:]]*$//')
        (echo > /dev/tcp/${domain}/${port}) &>/dev/null
        if [ $? -eq 0 ]; then
            info "Connection valid for \"${remote}\""
            remotesrc=$remote
            break
        fi

        # If we get here the connection did not work
        warning "No connection with \"${remote}\", testing the next remote..."
    done

    # If no source url is defined it means we did not find a valid remote url that we can connect to now
    if [ -z "$remotesrc" ]; then
        error "No connection with any remote found in \"${repoconfig}\", cannot update this mirror continuing with the next"
        continue
    fi

    # Many mirrors provide a filelist that is much faster to validate against first and takes less requests, 
    # So we start with that
    checkresult=""
    if [ -z "$filelistfile" ]; then
        info "The variable \"filelistfile\" is empty or not defined for \"${repoconfig}\""
    elif [ "$port" == "$RSYNC_port" ]; then
        checkresult=$(rsync --no-motd --dry-run --out-format="%n" "${remotesrc}/$filelistfile" "${mirrordst}/$filelistfile")
    else
        warning "The protocol used with \"${remotesrc}\" has not yet been implemented. Move another protocol higher up in 
list of remotes to solve this at the moment. Cannot update this mirror continuing with the next"
        continue
    fi

    # Check the results of the filelist against the local
    if [ -z "$checkresult" ] && [ ! -z "$filelistfile" ]; then
        info "The filelist is unchanged at \"${remotesrc}\", no update required for this mirror continuing with the next"
        continue
    fi

    # Create a new exlude file before running the update
    excludefile="${SCRIPTDIR}/${mirrorname}_exclude.txt"
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
        printf "$exclude\n" >> $excludefile
    done
    debug "excludes added to the file \"${excludefile}\""

    # Current disk spaces in bytes
    availablebytes=$(df -B1 $mirrordst | awk 'NR>1{print $4}' | tr -cd '[:digit:].')
    availablesize=$(echo $availablebytes | numfmt --to=iec-i)
    repobytes=$(du -sB1 "${mirrordst}/" | awk 'NR>0{print $1}' | tr -cd '[:digit:].')

    # Depending on what protocol the url has the approch on syncronizing the repo is different
    case $port in
        $RSYNC_PORT)
            # Set variables for the run
            opts=(-vrlptDSH --delete-excluded --delete-delay --delay-updates --exclude-from=$excludefile)
            updatelogfile="${LOGPATH}/$(date +%y%m%d%H%M)_${mirrorname}_rsyncupdate.log"

            # First validate that there is enough space on the disk
            transferbytes=$(rsync "${opts[@]}" --dry-run --stats "${remotesrc}/" "${mirrordst}/" | grep -i "Total transferred" \
            | sed 's/[^0-9]*//g')

            # Convert bytes into human readable
            transfersize=$(echo $transferbytes | numfmt --to=iec-i)
            info "This synchronization will require ${transfersize}B on local storage"
                
            if [ $transferbytes -gt $availablebytes ]; then
                error "Not enough space on disk! This transfer needs ${transfersize}B of ${availablesize}B available. 
Cannot update this mirror continuing with the next"
                continue
            fi

            # header for the new log fil
            print_header_updatelog "rsync" "$remotesrc" "$mirrordst" "$transfersize" "$availablesize" "$updatelogfile" "${opts[*]}"

            # Start updating
            rsync "${opts[@]}" "${remotesrc}/" "${mirrordst}/" >> "$updatelogfile" 2>&1

            # Finished
            info "Finished updating mirror \"${mirrorname}\", log found at \"${updatelogfile}\""
            ;;
        $HTTP_PORT|$HTTPS_PORT)

            # TODO: First use httpsync to get a list of out of sync files

            TEST=$(httpsync "${remotesrc}/" "${mirrordst}/" "${excludequeries[*]}")
            echo "Recursive filelist: ${TEST[*]}"

            # Set variables for the run
            opts=(-mpEk --no-parent --convert-links --random-wait robots=off --reject="$(tr '\n' ',' < $excludefile)")
            updatelogfile="${LOGPATH}/$(date +%y%m%d%H%M)_${mirrorname}_httpupdate.log"

            # First validate that there is enough space on the disk
            remote_repobytes=$(wget "${opts[@]}" --spider  "${remotesrc}/" | grep -i "Length" | gawk '{sum+=$2}END{print sum}')
            transferbytes=$(expr $remote_repobytes - $repobytes)
            transfersize=$(echo $transferbytes | numfmt --to=iec-i)
            info "This synchronization will require ${transfersize}B on local storage"

            if [ $transferbytes -gt $availablebytes ]; then
                error "Not enough space on disk! This transfer needs ${transfersize}B of ${availablesize}B available. 
Cannot update this mirror continuing with the next"
                continue
            fi


            ;;
        *)
            warning "The protocol defined for \"${remotesrc}\" is invalid, cannot update this mirror continuing with the next"
            ;;
    esac
done

# Finished
log "Synchronization process finished"
rm -f "$LOCKFILE"

exit 0