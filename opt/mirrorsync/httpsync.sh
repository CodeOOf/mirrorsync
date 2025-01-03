#!/bin/env bash
# 
# Mirrorsync - httpsync.sh
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
COMPDATE_FORMAT="+%Y%m%d%H%M%S"
FILEDATE_FORMAT="+%Y%m%d%H%M.%S"
DIRPERM=755
FILEPERM=644

# Log functions
log() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }
info() { if [ $VERBOSE_ARG -eq 1 ]; then log "$*" >&2; fi }
debug() { if [ $DEBUG_ARG -eq 1 ]; then log "Debug: $*" >&2; fi }
warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { error "$*, exiting"; exit 1; }
error_argument() { error "$*, exiting"; usage >&2; exit 1; }
actionlog() { printf "%s\n" "$*" >&2; }

# Arguments Help
usage() {
    cat << EOF
Usage: $0 [options] <SOURCE> <DESTINATION>

Arguments:

  -h, --help
    Display this usage message and exit.

  --chmod=DXXX,FYYY
    Set specific file or directory permission on the destination mirror. Only numeric chmod is allowed.
    Default: D${DIRPERM},F${FILEPERM}

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

# Temporary arguments variables
chmod_arg=""

# Arguments Parser
while [ "$#" -gt 0 ]; do
    case $1 in
        --chmod=*) chmod_arg="${1#*=}";;
        -d|--debug) DEBUG_ARG=1;;
        --delete-after) DELETE_AFTER=1;;
        --delete-excluded) DELETE_EXCLUDE=1;;
        --exclude) EXCLUDES=($2);;
        --exclude-from=*) EXCLUDE_FILE="${1#*=}";;
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
    shift || error_argument "Option '${1}' requires a value"
done

# Populate the source and destination
SRC="${POSITIONAL_ARGS[0]}"
DST="${POSITIONAL_ARGS[1]}"

# If the destination path is empty then do from user position
if [ -z "$DST" ]; then DST=$(pwd); fi

# If chmod argument is set, change the numbers
if [ ! -z "$chmod_arg" ]; then
    dirnum_test=0
    filenum_test=0

    # Exctract the first 3 numbers after each character match
    [[ "${TEST}" =~ [dD]([[:digit:]]{3}) ]] && dirnum_test="${BASH_REMATCH[1]}"
    [[ "${TEST}" =~ [fF]([[:digit:]]{3}) ]] && filenum_test="${BASH_REMATCH[1]}"

    debug "Extracted the following chmod=D${dirnum_test},F${filenum_test}"

    # Test if numbers are correct then add them to global
    if [ $dirnum_test -gt 0 ]; then DIRPERM=$dirnum_test; fi
    if [ $filenum_test -gt 0 ]; then FILEPERM=$filenum_test; fi

fi

# Function to validate if value is matched in a array of queries
# Usage: arraymatch "value_to_test" "array of values to validate"
arraymatch() {
    local queries=($2)
    local value="$1"
    local value_extra="$value"

    # If the value starts with "/" remove it
    if [ "${1:0:1}" == "/" ]; then value=${1:1}; fi
    # If value ends with "/" then add it as a extra test
    if [ "${value:0-1}" == "/" ]; then value_extra="${value:0:-1}"; fi

    for query in "${queries[@]}"
    do
        if [[ "$value" == $query ]] || [[ "$value_extra" == $query ]]; then 
            debug "The value \"${1}\" matched query \"${query}\""; 
            return 0; 
        fi
    done

    return 1
}

# This is a recursive function that will parse through a website with listed items and compare with local
# returning a list of itemes out of sync
# Usage: parsefilelist "http://example.com/pub/repo/" "/my/local/destination/" "(EXCLUDE/,*FILES,and~,/dirs)"
# With the ending slash on paths and urls
# excludes starting with "/" only excludes from root
parsefilelist() {
    local baseurl=$1
    local localpath=$2
    local querylist=($3)
    local rootqueries=()
    local localfiles=(${localpath}*)

    # If empty then the command wont execute, so the command becomes the entry
    if [[ "$localfiles" =~ "${localpath}"\* ]]; then localfiles=(); fi

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

        # Check if the href ends with slash (to indicate a directory) 
        # while not being a parent link like "/","./" or "../"
        if ! [[ "$href" =~ ^\.*\/ ]] && [ "${href:0-1}" == "/" ]; then
            # Find this path in localfiles and remove it
            for index in "${!localfiles[@]}"
            do
                if [ "${localfiles[$index]}" == "${dst:0:-1}" ]; then
                    unset localfiles[$index]
                fi
            done

            # Call recursivly until no more directories are found
            if [ $RECURSIVE_ARG -eq 1 ]; then
                parsefilelist "$url" "$dst" "${querylist[*]}" >&2
            fi
        # As long as it is not ending slash, assume as file
        elif [ "${href:0-1}" != "/" ]; then
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

                # Check if modified date exists at source
                local modified_src=""
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

                            local compdate_src=$(date -d "$modified_src" "$COMPDATE_FORMAT")
local compdate_dst=$(date -d "$modified_dst" "$COMPDATE_FORMAT")

                            # Check if file is changed based on date if date was extracted from source
                            if [ ! -z "$modified_src" ] && [[ $compdate_src > $compdate_dst ]]; then
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
                    local modified_file=$(date -d "$modified_src" "$FILEDATE_FORMAT")
                    local filesize=$(echo $bytes_src | numfmt --to=iec-i)

                    debug "Added a file of size ${filesize}B from \"${url}\" to the list, it was last modifed " \
                          "\"${modified_str}\""
                    # Add to the array
                    SYNCLIST+=("${url},${dst},${bytes_src},${href},${modified_file}")
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
            SYNCLIST+=(",${localfile},,,")
        done
    fi
}

# Read all the exclude patterns from the file
if [ ! -z "$EXCLUDE_FILE" ]; then
    IFS=$'\n' read -d '' -r -a EXCLUDES < $EXCLUDE_FILE
fi

# If the source and destination is not ending with a slash, add it
if [ "${SRC:0-1}" != "/" ]; then SRC="${SRC}/"; debug "Added a \"/\" to the source: $SRC"; fi
if [ "${DST:0-1}" != "/" ]; then DST="${DST}/"; debug "Added a \"/\" to the destination: $DST"; fi

info "Validating files from remote \"${SRC}\" against \"${DST}\""
parsefilelist "$SRC" "$DST" "${EXCLUDES[*]}" >&2
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
        if [ ! -z "${syncinfo[0]}" ]; then ((transfer_size+=${syncinfo[2]})); fi
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
            actionlog "*NEW* ${syncinfo[1]}"
        else
            actionlog "Remove ${syncinfo[1]}"
        fi
    done

    info "Done"
    exit 0
fi

info "Synchronization progress starting"
opts=(--silent)
# Main Sync
for item in "${SYNCLIST[@]}"
do
    IFS=',' read -r -a syncinfo <<< "$item"
    if [ ! -z "${syncinfo[0]}" ]; then 
        if [ $DELETE_AFTER -eq 1 ]; then
            tmpfile="/tmp/${syncinfo[3]}"

            # Begin transfer of file
            actionlog "Transfering \"${syncinfo[0]}\" to \"${tmpfile}\""
            curl "${opts[@]}" "${syncinfo[0]}" --output "$tmpfile" 2>&1

            # Check that the file exists then remove it
            if [ -f "${syncinfo[1]}" ]; then
                actionlog "Removing ${syncinfo[1]}"
                rm "${syncinfo[1]}" 2>&1
            fi

            # Verify the file still exists then move it
            if [ -f "$tmpfile" ]; then
                dstdir="$(dirname "$tmpfile")"
                # Ensure that a destination directory exists before moving
                if mkdir -m $DIRPERM -p "$dstdir" 2>&1; then
                    # Then move the file
                    debug "Moving the file \"${tmpfile}\" to \"${syncinfo[1]}\""
                    mv "$tmpfile" "${syncinfo[1]}" 2>&1

                    debug "Setting permission $FILEPERM on \"${syncinfo[1]}\""
                    chmod $FILEPERM "${syncinfo[1]}"

                    debug "Changing the files modification date to remotes"
                    touch -t "${syncinfo[4]}" "${syncinfo[1]}"
                else
                    error "Could not create the directory \"${dstdir}\" for the transfered file \"${tmpfile}\""
                fi
            else
                error "The transfered temporary file \"${tmpfile}\" is missing"
            fi
        else
            # Check that the file exists then remove it
            if [ -f "${syncinfo[1]}" ]; then
                actionlog "Removing ${syncinfo[1]}"
                rm "${syncinfo[1]}" 2>&1
            fi

            # Ensure that a destination directory exists before transfering
            dstdir="$(dirname "${syncinfo[1]}")"
            if mkdir -m $DIRPERM -p "$dstdir" 2>&1; then
                # Begin transfer of file
                actionlog "Transfering \"${syncinfo[0]}\" to \"${syncinfo[1]}\""
                curl "${opts[@]}" "${syncinfo[0]}" --output "${syncinfo[1]}" 2>&1

                debug "Setting permission $FILEPERM on \"${syncinfo[1]}\""
                chmod $FILEPERM "${syncinfo[1]}"

                debug "Changing the files modification date to remotes"
                touch -t "${syncinfo[4]}" "${syncinfo[1]}"
            else
                error "Could not create the directory \"${dstdir}\" for the remote file \"${syncinfo[0]}\""
            fi
        fi
    else
        if [ -f "${syncinfo[1]}" ]; then
            actionlog "Removing ${syncinfo[1]}"
            rm "${syncinfo[1]}" 2>&1
        fi

        # Continue to remove if directory exists and is empty
        dstdir="$(dirname "$tmpfile")"
        if [ -d "$dstdir" ] &&  [ -n "$(find $dstdir -maxdepth 0 -type d -empty 2>&1)" ]; then
            actionlog "Removing empty directory \"${dstdir}\""
            rm -r "$dstdir"
        fi

    fi
done

log "Synchronization process finished"
exit 0