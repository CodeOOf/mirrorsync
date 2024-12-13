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

# Verify config file is readable
if [ ! -r "$CONFIGFILE" ]; then
    echo "Error: The script configfile \"$CONFIGFILE\" is not availble or readable, exiting..."
    exit 1
else
    source "$CONFIGFILE"
fi

# Verify repo path exists
if [ ! -d "$REPOCONFIG_DIR" ]; then
    echo "Error: The directory \"$REPOCONFIG_DIR\" does not exist, exiting..."
    exit 1
fi

# Verify that there are any mirror repositories to work with
REPOCONFIGS=(${REPOCONFIG_DIR}/*.conf)
if [ "${#REPOCONFIGS[@]}" == 0 ]; then
    echo "Error: The directory \"$REPOCONFIG_DIR\" is empty or contains no config files, please provide repository "
    echo "config files that this script can work with, exiting..."
    exit 1
fi

# Verify that current path is writable
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
if [ ! -w "$SCRIPTDIR" ]; then
    echo "Error: The directory where this script is located is not writable for this user. This is required for the "
    echo "lockfile to avoid multiple simultaneous runs of the script, exiting..."
    exit 1
fi

# Validate current settings
if [ -z "$LOGPATH" ]; then 
    echo "Info: Missing variable \"LOGPATH\" at \"$CONFIGFILE\", using default."
    LOGPATH="/var/log/mirrorsync"
fi

if [ ! -w "$LOGPATH" ]; then
    echo "Error: The log directory is not writable for this user: $LOGPATH"
    exit 1
fi

if [ -z "$LOGFILENAME" ]; then 
    echo "Info: Missing variable \"LOGFILENAME\" at \"$CONFIGFILE\", using default."
    LOGFILENAME="$0"
fi
LOGFILE="${LOGPATH}/${LOGFILENAME}.log"

if [ -z "$DSTPATH" ]; then 
    printf "[%(%F %T)T] Error: Missing variable \"DSTPATH\" at \"%s\". It is required to know where to write the " \
    "mirror data, exiting...\n" -1 "$CONFIGFILE" >> "$LOGFILE" 2>&1
    exit 1
fi

if [ ! -w "$DSTPATH" ]; then
    printf "[%(%F %T)T] Info: The destination path \"%s\" is not writable for this user, exiting...\n" \
    -1 "$DSTPATH" >> "$LOGFILE" 2>&1
    exit 1
fi

# Check for existing lockfile to avoid multiple simultaneously running syncs
# If lockfile exists but process is dead continue anyway
if [ -e "$LOCKFILE" ] && ! kill -0 "$(< "$LOCKFILE")" 2>/dev/null; then
        printf "[%(%F %T)T] Warning: lockfile exists but process dead, continuing...\n" -1 >> "$LOGFILE" 2>&1
        rm -f "$LOCKFILE"
elif [ -e "$LOCKFILE" ]; then
        printf "[%(%F %T)T] Info: A update is already in progress, exiting...\n" -1 >> "$LOGFILE" 2>&1
        exit 1
fi

# Main script
printf '%s\n' "$$" > "$LOCKFILE"

# Start updating each mirror repo
printf "[%(%F %T)T] Info: Synchronization process starting...\n" -1 >> "$LOGFILE" 2>&1
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
        printf "[%(%F %T)T] Error: no local directory is defined in \"%s\", cannot update this mirror continuing with 
the next repository...\n" -1 "$FILE" >> "$LOGFILE" 2>&1
        continue
    elif [ ! -w "$DST" ]; then
        printf "[%(%F %T)T] Error: The path \"%s\" is not writable, cannot update this mirror continuing with the next 
repository...\n" -1 "$DST" >> "$LOGFILE" 2>&1
        continue
    elif [ ! -d "$DST" ]; then
        printf "[%(%F %T)T] Warning: A local path for \"%s\" does not exists, will create one...\n" -1 "$LOCALDIR" \
        >> "$LOGFILE" 2>&1
        if [ ! mkdir "$DST" 2>/dev/null ]; then
            printf "[%(%F %T)T] Error: The path \"%s\" could not be created, cannot update this mirror continuing with 
the next repository...\n" -1 "$DST" >> "$LOGFILE" 2>&1
            continue
        fi
    fi
    
    # Validate the remotes variable is a array
    if [ ! $(declare -p REMOTES | grep '^declare -a') ]; then
        printf "[%(%F %T)T] Error: The remotes defined for \"%s\" is invalid, needs to be a array. cannot update this 
mirror continuing with the next repository...\n" -1 "$LOCALDIR" >> "$LOGFILE" 2>&1
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
                printf "[%(%F %T)T] Error: The remote path \"%s\" contains invalid protocol\n" -1 "$REMOTE" >> \
                "$LOGFILE" 2>&1
                continue
                ;;
        esac
        
        # Make a connection test against the url on that port to validate connectivity
        DOMAIN=$(echo $REMOTE | awk -F[/:] '{print $4}')
        (echo > /dev/tcp/${DOMAIN}/${PORT}) &>/dev/null
        if [ $? -eq 0 ]; then
             printf "[%(%F %T)T] Info: Connection valid for \"%s\", continuing with this remote...\n" -1 "$REMOTE" >> \
            "$LOGFILE" 2>&1
            SRC=$REMOTE
            break
        fi

        # If we get here the connection did not work
        printf "[%(%F %T)T] Warning: No connection with \"%s\", continuing with next remote...\n" -1 "$REMOTE" >> \
        "$LOGFILE" 2>&1

    done

    # If no source url is defined it means we did not find a valid remote url that we can connect to now
    if [ -z "$SRC" ]; then
        printf "[%(%F %T)T] Error: No connection with any source provided in \"%s\", cannot update this mirror 
continuing with the next repository...\n" -1 "$FILE" >> "$LOGFILE" 2>&1
        continue
    fi

    # Many mirrors provide a filelist that is much faster to validate against first and takes less requests, 
    # So we start with that
    CHECKRESULT=""
    if [ -z "$FILELISTFILE" ]; then
        printf "[%(%F %T)T] Info: The variable \"FILELISTFILE\" is empty or not defined at \"%s\", continuing...\n" -1 \
        "$FILE" >> "$LOGFILE" 2>&1
    elif [ "$PORT" == "$RSYNC_PORT" ]; then
        CHECKRESULT=$(rsync --no-motd --dry-run --out-format="%n" "${SRC}/$FILELISTFILE" "${DST}/$FILELISTFILE")
    else
        printf "[%(%F %T)T] Warning: The protocol used with \"%s\" has not yet been implemented. Move another protocol 
higher up in list of remote sources if there are any to solve this at the moment. Cannot update this mirror continuing 
with the next repository...\n" -1 "$SRC" >> "$LOGFILE" 2>&1
        continue
    fi

    # Check the results of the filelist against the local
    if [ -z "$CHECKRESULT" ] && [ ! -z "$FILELISTFILE" ]; then
        printf "[%(%F %T)T] Info: The filelist file is unchanged at \"%s\", no update available for this mirror 
continuing with the next repository...\n" -1 "$SRC" >> "$LOGFILE" 2>&1
        continue
    fi

    # Create a new exlude file before running the update
    EXCLUDEFILE="${SCRIPTDIR}/${LOCALDIR}_exclude.txt"
    # Clear file
    > $EXCLUDEFILE

    # Validate the exclude list variable is a array
    if [ ! $(declare -p EXCLUDELIST | grep '^declare -a') ]; then
        printf "[%(%F %T)T] Error: The exclude list defined for \"%s\" is invalid or no array, will ignore it.\n" -1 \
        "$LOCALDIR" >> "$LOGFILE" 2>&1
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
            if [ "$TRANSFERBYTES" > "$AVAILABLEBYTES" ]; then
                printf "[%(%F %T)T] Error: Not enough space on disk! The transfer needs %i bytes of %i available. 
Cannot update this mirror continuing with the next repository...\n" -1 "$TRANSFERBYTES" "$AVAILABLEBYTES" "$LOCALDIR" \
                >> "$LOGFILE" 2>&1
                continue
            fi

            # Header for the new log fil
            printf "Using the following arguments for this run:\n[" >> "$UPDATELOGFILE" 2>&1
            printf "%s \n" "${OPTS[*]}" >> "$UPDATELOGFILE" 2>&1
            printf "This transfer will require: %i/%i bytes" "$TRANSFERBYTES" "$AVAILABLEBYTES" >> "$UPDATELOGFILE" 2>&1
            printf "]\n\n---\n" >> "$UPDATELOGFILE" 2>&1

            # Start updating
            rsync "${opts[@]}" "${SRC}/" "${DST}/" >> "$UPDATELOGFILE" 2>&1

            # Finished
            printf "[%(%F %T)T] Info: Finished updating mirror \"%s\": \"%s\s.\n" -1 "$LOCALDIR" "$UPDATELOGFILE" \
            >> "$LOGFILE" 2>&1
            ;;
        *)
            printf "[%(%F %T)T] Warning: The protocol used with \"%s\" has not yet been implemented. Move another 
protocol higher up in list of remote sources if there are any to solve this at the moment. Cannot update this mirror 
continuing with the next repository...\n" -1 "$SRC" >> "$LOGFILE" 2>&1
            ;;
    esac
done

# Finished
printf "[%(%F %T)T] Info: Synchronization process finished.\n" -1 >> "$LOGFILE" 2>&1
rm -f "$LOCKFILE"

exit 0