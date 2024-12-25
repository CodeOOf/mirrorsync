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
IGNORE_EXT=0
LIST_ONLY=0
RECURSIVE_ARG=0
STATS=0
VERBOSE_ARG=0
POSITIONAL_ARGS=()
SRC=""
DST=""
SYNCLIST=()
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"

# Log functions
log() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }
info() { if [ $VERBOSE_ARG -eq 1 ]; then log "$*" >&2; fi }
debug() { if [ $DEBUG_ARG -eq 1 ]; then log "Debug: $*" >&2; fi }
warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { error "$*, exiting"; exit 1; }
error_argument() { error "$*, exiting"; usage >&2; exit 1; }
progress() { printf "%s\n" "$*" >&2; }

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

  -ie, --ignore-external
    Ignores any files that are linked outside of the current domain

  -l, --list-only
    Only outputs what files that would change

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
        --delete-excluded) DELETE_EXCLUDE=1;;
        --exclude) EXCLUDES=($2);;
        --exclude-file) EXCLUDE_FILE="$2";;
        -h|--help) usage; exit 0;;
        -hr|--human-readable) HUMAN_READABLE=1;;
        -ie|--ignore-external) IGNORE_EXT=1;;
        -l|--list-only) LIST_ONLY=1;;
        -r|--recursive) RECURSIVE_ARG=1;;
        --stats) STATS=1;;
        -v|--verbose) VERBOSE_ARG=1;;
        --) shift; break;;
        -*) error_argument "Unknown option: '$1'";;
        *)
            POSITIONAL_ARGS+=("$1")
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
    local baseurl=$1
    local localpath=$2
    local querylist=($3)
    local rootqueries=()
    local localfiles=(${localpath}/*)

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
    for href in $(curl -sf "$baseurl" | sed -n "/href/ s/.*href=['\"]\([^'\"]*\)['\"].*/\1/gp")
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
                httpssynclist "$url" "$dst" "${querylist[*]}" >&2
            fi
        # As long as it is not ending slash, assume as file
        elif [ "${href: -1:1}" != $'/' ]; then
            # Verify that url is OK
            local http_status=$(curl -o /dev/null -sIw '%{http_code}' "$url")
            if [ $http_status -eq 200 ]; then
                # Extract content information from header response
                local header=$(curl -sfI "$url")

                # Check if location exists first so that we extract information from the file source
                local location=$(echo "${header[*]}" | grep -i "location" | awk '{print $2}' \
                | sed -z 's/[[:space:]]*$//')
                if [ ! -z "$location" ]; then
                    info "Found file at another domain \"${location}\" for \"${dst}\""
                    header=$(curl -sfI "$location")
                    url="$location"
                fi

                # Extract file information
                local bytes_src=$(echo "${header[*]}" | grep -i "Content-Length" | awk '{print $2}' \
                | tr -cd '[:digit:].')
                local modified_header=$(echo "${header[*]}" | grep -i "Last-modified" \
                | awk -v 'IGNORECASE=1' -F'Last-modified:' '{print $2}')
                if [ ! -z "${modified_header}" ]; then 
                    modified_src=$(date -d "$modified_header")
                else
                    debug "No modification date found for \"${url}\""
                fi

                if [ ! -z "$bytes_src" ] && [ $bytes_src -gt 0 ]; then
                    # Try to find this file at local destination
                    for index in "${!localfiles[@]}"
                    do
                        if [ "${localfiles[$index]}" == "$dst" ]; then
                            unset localfiles[$index]
                            # Get local file information
                            local bytes_dst=$(du -k "$dst" | cut -f1)
                            local modified_dst=$(date -r "$dst")

                            # Check if file is changed based on date if date was extracted
                            if [ ! -z $modified_src ] && [ $modified_src > $modified_dst ]; then
                                info "Local file \"${dst}\" is unchanged at remote based on date"

                                # Continue with the next item in the loop above this inner as the file is unchanged
                                continue 2
                            fi

                            # If we cannot test by date, test with size
                            if [ $bytes_src -eq $bytes_dst ]; then 
                                info "Local file \"${dst}\" is unchanged at remote based on size"

                                # Continue with the next item in the loop above this inner as the file is unchanged
                                continue 2
                            fi

                            # Break this first loop as we found the file
                            info "The remote file \"${url}\" has changed from local \"${dst}\""
                            break
                        fi
                    done

                    if [ $IGNORE_EXT -eq 1 ] && [ ! -z "$location" ]; then 
                        info "Local file \"${dst}\" has changed and is found at another remote domain, to be ignored";
                        continue
                    fi

                    local modified_str=$(date -d "$modified_src" "$DATE_FORMAT")
                    local filesize=$(echo $bytes_src | numfmt --to=iec-i)

                    debug "Added a file of size ${filesize}B from \"${url}\" to the list, it was last modifed " \
                          "\"${modified_str}\""
                    # Add to the array
                    SYNCLIST+=("${url},${dst},${bytes_src},${href}")
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
            SYNCLIST+=(",${localfile},,")
        done
    fi
}

# Read all the exclude patterns from the file
if [ ! -z "$EXCLUDE_FILE" ]; then
    IFS=$'\n' read -d '' -r -a EXCLUDES < $EXCLUDE_FILE
fi

# If the source and destination is not ending with a slash, add it
if [ "${SRC:-1:1}" != "/" ]; then SRC="${SRC}/"; debug "Added a \"/\" to the source: $SRC"; fi
if [ "${DST:-1:1}" != "/" ]; then DST="${DST}/"; debug "Added a \"/\" to the destination: $DST"; fi

info "Validating files from remote \"${SRC}\" against \"${DST}\""
httpssynclist "$SRC" "$DST" "${EXCLUDES[*]}" >&2
info "Validation finished"

if [ ${#SYNCLIST[@]} -eq 0 ]; then
    log "No relevant files found at \"${SRC}\", done"
    exit 0
fi

# If we only suppose to print the transfer size
if [ $STATS -eq 1 ]; then
    transfer_size=0
    for item in "${SYNCLIST[@]}"
    do
        IFS=',' read -r -a syncinfo <<< "$item"
        if [ ! -z "${syncinfo[0]}" ]; then transfer_size=$(expr $transfer_size + ${syncinfo[2]}); fi
    done

    # Convert the output to human readable numbers
    if [ $HUMAN_READABLE -eq 1 ]; then transfer_size=$(echo $transfer_size | numfmt --to=iec-i); fi

    printf "%s\n" "$transfer_size" >&2
    exit 0
fi

# If we only suppose to print the list
if [ $LIST_ONLY -eq 1 ]; then
    for item in "${SYNCLIST[@]}"
    do
        IFS=',' read -r -a syncinfo <<< "$item"
        if [ ! -z "${syncinfo[0]}" ]; then 
            progress "*NEW* ${syncinfo[1]}"
        else
            progress "Remove ${syncinfo[1]}"
        fi
    done

    info "Done"
    exit 0
fi

info "Synchronization progress starting"
# Main Sync
for item in "${SYNCLIST[@]}"
do
    IFS=',' read -r -a syncinfo <<< "$item"
    if [ ! -z "${syncinfo[0]}" ]; then 
        progress "Transfering ${syncinfo[1]}"
        if [ $DELETE_AFTER -eq 1 ]; then
            tmpfile="/tmp/${syncinfo[3]}"
            curl "${syncinfo[0]}" --output "$tmpfile" 2>&1
            rm "${syncinfo[1]}" 2>&1
            mv "$tmpfile" "${syncinfo[1]}" 2>&1
        else
            rm "${syncinfo[1]}" 2>&1
            curl "${syncinfo[0]}" --output "${syncinfo[1]}" 2>&1
        fi
    else
        progress "Removing ${syncinfo[1]}"
        rm -r "${syncinfo[1]}"
    fi
done

log "Synchronization process finished"
exit 0