#!/bin/env bash
# 
# Mirrorsync - curlscrape.sh
# Author: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

# Log functions for standard output
log_stdout() { printf "[%(%F %T)T] %s\n" -1 "$*" >&2; }

# Log functions
log() { log_stdout "$*" >&2; }
info() { log "$*" >&2; }
debug() { log "Debug: $*" >&2; }
warning() { log "Warning: $*" >&2; }
error() { log "Error: $*" >&2; }
fatal() { error "$*, exiting..."; exit 1; }

MINMAJOR=40
MINMINOR=10

has_exclude() {
    EXCLUDES=($2)
    FOUND_MATCH=0

    for EXCLUDE in "${EXCLUDES[@]}"
    do
        debug "Testing if \"${1}\" == \"${EXCLUDE}\""
        if [ "$1" == $EXCLUDE ]; then FOUND_MATCH=1; debug "Yes match!"; break; fi
    done

    echo $FOUND_MATCH
}

httpsync() {
    FILELIST=()
    BASEURL=$1
    LOCALPATH=$2
    EXCLUDES=($3)
    ROOTEXCLUDE=()

    # Extract all root items to exlude
    for INDEX in "${!EXCLUDES[@]}"
    do
        if [ "${EXCLUDES[$INDEX]:0:1}" == "/" ]; then
            ROOTEXCLUDE+=("${EXCLUDES[$INDEX]:1}")
            unset EXCLUDES[$INDEX]
        fi
    done
    debug "Excludelist only for \"${BASEURL}\": ${ROOTEXCLUDE[*]}"

    # Get all the links on that page
    debug "Begin scraping paths from \"$BASEURL\""
    for HREF in $(curl -s "$BASEURL" | sed -n "/href/ s/.*href=['\"]\([^'\"]*\)['\"].*/\1/gp")
    do 
        debug "Now working on relative path: $HREF"
        # Constructs the new url, assuming relative paths at remote
        URL="${BASEURL}$HREF"
        DST="${LOCALPATH}$HREF"

        # Check if part of exclude list
        if [ has_exclude "$HREF" "${EXCLUDES[*]}" 2>&1 ] || [ has_exclude "$HREF" "${ROOTEXCLUDE[*]}" 2>&1 ]; then
            debug "The path \"${HREF}\" is part of the exclude"
            continue
        fi

        # Check if the href ends with slash and not parent or begins with slash
        if [ "${#HREF}" -gt 1 ] && [ "${HREF: -1:1}" == $'/' ]  && 
        [ "${HREF: -2:2}" != $"./" ] && [ "${HREF: 0:1}" != $'/' ]; then
            # Call recursivly until no more directories are found
            RECURSIVECALL=$(httpsync "$URL" "$DST" "${EXCLUDES[*]}" | tr -d '\0')

            # Only add to collection if array is populated
            IS_ARRAY=$(declare -p RECURSIVECALL | grep '^declare -a')
            if [ -z "$IS_ARRAY" ]; then
                FILELIST+=$RECURSIVECALL
            fi
        # As long as it is not ending slash, assume as file
        elif [ "${HREF: -1:1}" != $'/' ]; then
            BYTES=""
            MODIFIED=""
            # Verify that URL exists
            if curl -ivs "$URL" 2>&1; then
                # Extract content information from header response
                HEADER=$(curl -sI "$URL")

                # Check if location exists first so that we extract information from the file source
                LOCATION=$(echo "${HEADER[*]}" | grep -i "Location" | awk '{print $2}' | sed -z 's/[[:space:]]*$//')
                if [ ! -z "$LOCATION" ]; then
                    info "Found file at another domain \"${LOCATION}\" for \"${DST}\""
                    HEADER=$(curl -sI "$LOCATION")
                    URL=$LOCATION
                fi

                # Extract file information
                BYTES=$(echo "${HEADER[*]}" | grep -i "Content-Length" | awk '{print $2}' | tr -cd '[:digit:].')
                MODIFIED_STR=$(echo "${HEADER[*]}" | grep -i "Last-Modified"  | awk -v 'IGNORECASE=1' -F'Last-Modified:' '{print $2}')
                MODIFIED=$(date -d "$MODIFIED_STR" "+%Y-%m-%d %H:%M:%S")

                if [ ! -z "$BYTES" ] && [ $BYTES -gt 0 ]; then
                    FILESIZE=$(echo $BYTES | numfmt --to=iec-i)
                    debug "Added a file of size ${FILESIZE}B from \"${URL}\" to the list, it was last modifed \"${MODIFIED}\""
                    # Add to the array
                    FILE=("$URL" "$MODIFIED" "$BYTES" "$DST")
                    FILELIST+=($FILE)
                else
                    debug "Not a file \"$URL\", ignoring path"
                fi
            else
                info "Invalid URL constructed at remote: $URL"
            fi
        else
            debug "Ignoring parent path \"${HREF}\" at remote: $BASEURL"
        fi
    done
    echo "${FILELIST[*]}"
}

EXCLUDELIST=("*.txt")
DST="/data/test"

debug "Current exclude versions is up to v${MINMAJOR}.${MINMINOR}"
if [ $MINMAJOR -gt 0 ]; then
    for i in $(seq 0 $((MINMAJOR -1)))
    do
        EXCLUDELIST+=("/$i" "/$i.*")
    done
    if [ $MINMINOR -gt 0 ]; then
        for i in $(seq 0 $((MINMINOR -1)))
        do
            EXCLUDELIST+=("/$MINMAJOR.$i")
        done
    fi
fi
debug "Current generated excludelist is: ${EXCLUDELIST[*]}"


TEST=$(get_httpfilelist "${@}/" "${DST}/" "${EXCLUDELIST[*]}")
echo "Recursive filelist: ${TEST[*]}"