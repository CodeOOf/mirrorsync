#!/bin/env bash
# 
# Mirrorsync
# By: Viktor H. Ingre <viktor.ingre@codeoof.com>
#
# Latest version available at:
# https://github.com/CodeOOf/mirrorsync
#
# Copyright (c) 2024 CodeOOf

CONFIGFILE="/etc/mirrorsync/mirrorsync.conf"
REPOCONFIG_DIR="/etc/mirrorsync/repos.conf.d"
LOCKFILE="$0.lockfile"

RSYNC_PORT=873
HTTP_PORT=80
HTTPS_PORT=443

# Verify config file is readable
if [ ! -r "$CONFIGFILE" ]; then
    echo "$CONFIGFILE is not availble or readable, exiting..."
    exit 1
else
    source "$CONFIGFILE"
fi

# Verify repo path exists
if [ ! -d "$REPOCONFIG_DIR" ]; then
    echo "$REPOCONFIG_DIR does not exist, used to read out different mirror repos to syncronize from, exiting..."
    exit 1
fi

# Verify that there are any mirror repositories to work with
REPOCONFIGS=(find $REPOCONFIG_DIR -type f -name "*.conf")
if [ -z "${REPOCONFIGS[@]}" ]; then
    echo "$REPOCONFIG_DIR is empty or no config files, please provide mirror repos for this script to work with, 
    exiting..."
    exit 1
fi

# Verify that current path is writable
if [ ! -w "$PWD" ]; then
    echo "Current directory of the script is not writable for this script, this is required for the lockfile to avoid 
    multiple simultaneous runs of the script, exiting..."
    exit 1
fi

# Validate current settings
if [ -z "$logpath" ]; then 
    echo "Missing config value \"logpath\", using default."
    logpath="/var/log/mirrorsync"
fi

if [ ! -w "$logpath" ]; then
    echo "Current log path directory is not writable for the script: $logpath"
    exit 1
fi

if [ -z "$logfile" ]; then 
    echo "Missing config value \"logfile\", using default."
    logfile="$0.log"
fi

if [ -z "$rsynclog_prefix" ]; then rsynclog_prefix="rsync"; fi

if [ -z "$dstpath" ]; then 
    echo "Missing config value \"dstpath\" that is required to know where to write the mirror data, exiting..."
    exit 1
fi

if [ ! -w "$dstpath" ]; then
    echo "Current destination directory is not writable for the script: 
    $dstpath"
    exit 1
fi

# Main script
printf '%s\n' "$$" > "$LOCKFILE"

# Check for existing lockfile to avoid multiple simultaneously running syncs
# If lockfile exists but process is dead continue anyway
if [ -e "$lockfile" ] && ! kill -0 "$(< "$lockfile")" 2>/dev/null; then
        printf "[%(%F %T)T] Warning: lockfile exists but process dead, continuing...\n" -1 >> "${logpath}/$logpath" 2>&1
        rm -f "$lockfile"
elif [ -e "$LOCKFILE" ]; then
        printf "[%(%F %T)T] Update already in progress...\n" -1 >> "${logpath}/$logpath" 2>&1
        exit 1
fi

# Start updating each mirror repo
printf "[%(%F %T)T] Started updating repos...\n" -1 >> "${logpath}/$logpath" 2>&1
for file in "$REPOCONFIGS"
do
    localpath=""
    filelistfile=""
    excludelist=""
    minmajor=0
    minminor=0
    remotes=()
    src=""
    PORT=0

    source $file

    # Define the new path
    dst="${dstpath}/$localpath"

    # Validate local path is defined and able to write to
    if [ -z "$localpath"]; then
        printf "[%(%F %T)T] Error: no local path is provided in \"$s\", cannot update this mirror\n" -1 "$file" >> \
        "${logpath}/$logpath" 2>&1
        break
    elif [ ! -w "$dst"]; then
        printf "[%(%F %T)T] Error: The path \"$s\" is not writable, cannot update this mirror\n" -1 \
        "$dst" >> "${logpath}/$logpath" 2>&1
    fi
    
    # Verify network connectivity against the remote and the select first available
    while [ "$remote" in "$remotes"]
    do
        # Check the protocol defined in the begining of the url and map it against a port number
        case "${remote%%:*}" in
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
                printf "[%(%F %T)T] Error: The remote path \"$s\" contains invalid protocol\n" -1 "$remote" >> \
                "${logpath}/$logpath" 2>&1
                ;;
        esac
        
        # Make a connection test against the url on that port to validate connectivity
        if [nc -z $remote $PORT 2>/dev/null]; then
            src=$remote
            break
        fi

        # If we get here the connection did not work
        printf "[%(%F %T)T] Warning: No connection with \"$s\", continuing with next...\n" -1 "$remote" >> \
        "${logpath}/$logpath" 2>&1

    done

    # If no source url is defined it means we did not find a valid remote url that we can connect to now
    if [ -z "$src" ]; then
        printf "[%(%F %T)T] Error: No connection with any source provided in\"$s\", cannot update this mirror\n" -1 \
        "$file" >> "${logpath}/$logpath" 2>&1
        break
    fi

    # Many mirrors provide a filelist that is much faster to validate against first and takes less requests, 
    # So we start with that
    checkresult=""
    if [ -z "$filelistfile" ]; then
        printf "[%(%F %T)T] Info: No filelistfile is provided in \"$s\"\n" -1 "$file" >> "${logpath}/$logpath" 2>&1
    elif [ "$PORT" == "$RSYNC_PORT" ]
        checkresult=$(rsync --no-motd --dry-run --out-format="%n" "${src}/$filelistfile" "${dst}/$filelistfile")
    else
        printf "[%(%F %T)T] Warning: This protocol used with \"$s\" has not yet been implemented, cannot update this 
        mirror now. Move a implemented protocol higher up in priority list of remote sources if there are any to solve 
        this at the moment\n" -1 "$src" >> "${logpath}/$logpath" 2>&1
    fi

    # Check the results of the filelist against the local
    if [ -z "$checkresult" ] && [ ! -z "$filelistfile"]; then
        printf "[%(%F %T)T] Info: Filelistfile is unchanged in \"$s\" with remote, will not update mirror\n" -1 \
        "$dst" >> "${logpath}/$logpath" 2>&1
        break
    fi

    # Depending on what protocol the url has the approch on syncronizing the repo is different
    case "$port" in
        "$RSYNC_PORT")
            ;;
        *)
            printf "[%(%F %T)T] Error: This protocol used with \"$s\" has not yet been implemented, cannot update this 
            mirror now. Move a implemented protocol higher up in priority list of remote sources if there are any to 
            solve this at the moment\n" -1 "$src" >> "${logpath}/$logpath" 2>&1
            ;;
    esac

done
exit 0

