#!/bin/env bash
# 
# Mirrorsync - httpssynclist.sh
# Author: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

# Global Variables
DEBUG_ARG=0
DELETE_AFTER=0
DELETE_EXCLUDE=0
EXCLUDES=()
EXCLUDE_FILE=""
HUMAN_READABLE=0
LIST_ONLY=0
PROGRESS_ARG=0
RECURSIVE_ARG=0
STATS=0
VERBOSE_ARG=0
POSITIONAL_ARGS=()
SRC=""
DST=""

# Log functions
log() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }
info() { if [ $VERBOSE_ARG -eq 1 ]; then log "$*" >&2; fi }
debug() { if [ $DEBUG_ARG -eq 1 ]; then log "Debug: $*" >&2; fi }
warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { error "$*, exiting"; exit 1; }
error_argument() { error "$*, exiting"; usage >&2; exit 1; }
progress() { printf "%s\n" -1 "$*" >&2; }

# Arguments Help
usage() {
    cat << EOF
Usage: $0 [options] <SOURCE> <DESTINATION>

Arguments:

  -h, --help
    Display this usage message and exit.

  -d, --debug
    Activate Debug Mode, provides a very detailed output to the system console.

  --delete-after
    Files are transferd to "/tmp" and deleted at destination after the transfer is complete.
    Default is deletion prior to transfer.
 
  --delete-excluded
    Delete files and directoris from destination that are excluded or not found at source

  --exclude=PATTERN
    Exclude files matching the following pattern

  --exclude-from=FILE
    Reads a list of patterns defined in a file and excludes   

  -hr, --human-readable
    Outputs the numbers in human-readable format

  -l, --list-only
    Only outputs what files that would change

  --progress
    Outputs the synchronization progress

  -r, --recursive
    Recurse into directories. 

  --stats
    Only calculates the transfer size and outputs the result

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
        -d|--debug) DEBUG_ARG=1;;
        --delete-after) DELETE_AFTER=1;;
        --delete-exclude) DELETE_EXCLUDE=1;;
        --exclude) EXCLUDES=($2); shift;;
        --exclude-file) EXCLUDE_FILE="$2"; shift;;
        -h|--help) usage; exit 0;;
        -hr|--human-readable) HUMAN_READABLE=1;;
        -l|--list-only) LIST_ONLY=1;;
        --progress) PROGRESS_ARG=1;;
        -r|--recursive) RECURSIVE_ARG=1;;
        --stats) STATS=1;;
        -v|--verbose) VERBOSE_ARG=1;;
        --) shift; break;;
        -*) error_argument "Unknown option: '$1'";;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
    shift || error_argument "Option '${arg}' requires a value"
done

# Populate the source and destination
SRC="${POSITIONAL_ARGS[0]}"
DST="${POSITIONAL_ARGS[1]}"

# If the destination path is empty then do from user position
if [ -z "$DST" ]; then DST=$(pwd); fi

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
# Usage: httpssynclist "http://example.com/pub/repo/" "/my/local/destination/" "(EXCLUDE/,*FILES,and~,/dirs)"
# With the ending slash on paths and urls
# excludes starting with "/" only excludes from root
httpssynclist() {
    local filelist=()
    local baseurl=$1
    local localpath=$2
    local querylist=($3)
    local rootqueries=()
    local localfiles=(${localpath}/*)
    local filentry=()

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
            # Find this path in localfiles and remove it
            for index in "${!localfiles[@]}"
            do
                if [ "${localfiles[$index]}" == "${dst:0:-1}" ]; then
                    unset localfiles[$index]
                fi
            done

            # Call recursivly until no more directories are found
            if [ $RECURSIVE_ARG -eq 1 ]; then
                local recursivecall=$(httpssynclist "$url" "$dst" "${querylist[*]}" | tr -d '\0')

                # Only add to collection if array is populated
                local is_array=$(declare -p recursivecall | grep '^declare -a')
                if [ -z "$is_array" ]; then
                    filelist+=$recursivecall
                fi
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
                local modified_str=$(echo "${header[*]}" | grep -i "Last-modified" \
                | awk -v 'IGNORECASE=1' -F'Last-modified:' '{print $2}')
                if [ ! -z "${modified_str}" ]; then 
                    modified=$(date -d "$modified_str")
                else
                    debug "No modification date found for \"${url}\""
                fi

                if [ ! -z "$bytes" ] && [ $bytes -gt 0 ]; then
                    # Try to find this file at local destination
                    for index in "${!localfiles[@]}"
                    do
                        if [ "${localfiles[$index]}" == "$dst" ]; then
                            unset localfiles[$index]
                            # Get local file information
                            local bytes_local=$(du -k "$dst" | cut -f1)
                            local modified_local=$(date -r "$dst")

                            # Check if file is changed based on date if date was extracted
                            if [ ! -z $modified ] && [ $modified > $modified_local ]; then
                                info "Local file \"${dst}\" is unchanged at remote based on date"

                                # Continue with the next item in the loop above this inner as the file is unchanged
                                continue 2
                            fi

                            # If we cannot test by date, test with size
                            if [ $bytes -eq $bytes_local ]; then 
                                info "Local file \"${dst}\" is unchanged at remote based on size"

                                # Continue with the next item in the loop above this inner as the file is unchanged
                                continue 2
                            fi

                            # Break this first loop as we found the file
                            info "The remote file \"${url}\" has changed from local \"${dst}\""
                            break
                        fi
                    done

                    local filesize=$(echo $bytes | numfmt --to=iec-i)
                    debug "Added a file of size ${filesize}B from \"${url}\" to the list, it was last modifed 
\"${modified}\""
                    # Add to the array
                    filentry=("$url" "$dst" "$bytes" "$href")
                    filelist+=($filentry)
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

    if [ $DELETE_EXCLUDE -eq 1 ]; then
        # Add the remaining local files for deletion
        for localfile in "${localfiles[@]}"
        do
            # Add to the array
            filentry=("" "$localfile" "" "")
            filelist+=($filentry)
        done
    fi

    # Return array
    echo "${filelist[*]}"
}

# Read all the exclude patterns from the file
if [ ! -z "$EXCLUDE_FILE" ]; then
    IFS=$'\n' read -d '' -r -a EXCLUDES < $EXCLUDE_FILE
fi

# If the source and destination is not ending with a slash, add it
if [ "${SRC:-1:1}" != "/" ]; then SRC="${SRC}/"; debug "Added a \"/\" to the source: $SRC"; fi
if [ "${DST:-1:1}" != "/" ]; then DST="${DST}/"; debug "Added a \"/\" to the destination: $DST"; fi

RESULTS=$(httpssynclist "$SRC" "$DST" "${EXCLUDES[*]}")

# If we only suppose to print the transfer size
if [ $STATS -eq 1 ]; then
    transfer_size=0
    for fileinfo in "${RESULTS[@]}"
    do
        if [ ! -z "${fileinfo[0]}" ]; then transfer_size+=$fileinfo[2]; fi
    done

    # Convert the output to human readable numbers
    if [ $HUMAN_READABLE -eq 1]; then transfer_size=$(echo $transfer_size | numfmt --to=iec-i); fi

    printf "%s" "$transfer_size" >%1
    exit 0
fi

# If we only suppose to print the list
if [ $LIST_ONLY -eq 1 ]; then
    for fileinfo in "${RESULTS[@]}"
    do
        if [ ! -z "${fileinfo[0]}" ]; then 
            progress "*NEW* ${FILE[1]}"
        else
            progress "Remove ${fileinfo[1]}"
        fi
    done

    info "Done"
    exit 0
fi

# Main Sync
for fileinfo in "${RESULTS[@]}"
do
    if [ ! -z "${fileinfo[0]}" ]; then 
        progress "Transfering ${fileinfo[1]}"
        if [ $DELETE_AFTER -eq 1 ]; then
            tmpfile="/tmp/${fileinfo[3]}"
            curl "${fileinfo[0]}" --output "$tmpfile" 2>&1
            rm "${fileinfo[1]}" 2>&1
            mv "$tmpfile" "${fileinfo[1]}" 2>&1
        else
            rm "${fileinfo[1]}" 2>&1
            curl "${fileinfo[0]}" --output "${fileinfo[1]}" 2>&1
        fi
    else
        progress "Removing ${fileinfo[1]}"
        rm -r "${fileinfo[1]}"
    fi
done

info "Done"
exit 0