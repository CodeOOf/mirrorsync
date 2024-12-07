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
if [[! -r "$CONFIGFILE"]]; then
    echo "$CONFIGFILE is not availble or readable, exiting..."
    exit 1
else
    source "$CONFIGFILE"
fi

# Verify repo path exists
if [[! -d "$REPOCONFIG_DIR"]]; then
    echo "$REPOCONFIG_DIR does not exist, used to read out different mirror repos to syncronize from, exiting..."
    exit 1
fi

# Verify that there are any mirror repositories to work with
REPOCONFIGS=(find $REPOCONFIG_DIR -type f -name "*.conf")
if [[! ${REPOCONFIGS[@]} ]]; then
    echo "$REPOCONFIG_DIR is empty or no config files, please provide mirror repos for this script to work with, 
    exiting..."
    exit 1
fi

# Verify that current path is writable
if [[! -w "$PWD"]]; then
    echo "Current directory of the script is not writable for this script, this is required for the lockfile to avoid 
    multiple simultaneous runs of the script, exiting..."
    exit 1
fi

# Validate current settings
if [[! "$logpath"]]; then 
    echo "Missing config value \"logpath\", using default."
    logpath="/var/log/mirrorsync"
fi

if [[! -w "$logpath"]]; then
    echo "Current log path directory is not writable for the script: $logpath"
    exit 1
fi

if [[! "$logfile"]]; then 
    echo "Missing config value \"logfile\", using default."
    logfile="$0.log"
fi

if [[! "$rsynclog_prefix"]]; then rsynclog_prefix="rsync"; fi

if [[! "$dstpath"]]; then 
    echo "Missing config value \"dstpath\" that is required to know where to write the mirror data, exiting..."
    exit 1
fi

if [[! -w "$dstpath"]]; then
    echo "Current destination directory is not writable for the script: 
    $dstpath"
    exit 1
fi

# Main script
printf '%s\n' "$$" > "$LOCKFILE"

# Check for existing lockfile to avoid multiple simultaneously running syncs
# If lockfile exists but process is dead continue anyway
if [[ -e "$lockfile" ]] && ! kill -0 "$(< "$lockfile")" 2>/dev/null; then
        printf "[%(%F %T)T] Warning: lockfile exists but process dead, continuing...\n" -1 >> "${logpath}/$logfile" 2>&1
        #logger -t mirrorsync "Warning: lockfile exists but process dead, continuing with mirrorsync."
        rm -f "$lockfile"
elif [[ -e "$LOCKFILE" ]]; then
        printf "[%(%F %T)T] Update already in progress...\n" -1 >> "${logpath}/$logfile" 2>&1
        #logger -t mirrorsync "Mirrorsync will not start: already in progress."
        exit 1
fi


printf "[%(%F %T)T] Started updating repos...\n" -1 >> "${logpath}/$logfile" 2>&1
for file in $REPOCONFIGS
do
    localpath=""
    filelistfile=""
    excludelist=""
    minmajor=0
    minminor=0
    remotes=()
    src=""
    proto=0

    source $file

    # Validate local path
    if [[! "$localpath"]]; then
        printf "[%(%F %T)T] Error: no local path is provided in \"$s\", cannot update this mirror\n" -1 "$file" >> 
        "${logpath}/$logfile" 2>&1
        break
    elif [[! -w "$dstpath/$localpath"]]; then
        printf "[%(%F %T)T] Error: The path \"$s\" is not writable, cannot update this mirror\n" -1 
        "$dstpath/$localpath" >> "${logpath}/$logfile" 2>&1
    fi
    
    # Check network connectivity against the remote
    while [[ $remote in $remotes]]
    do
        $proto="${remote%%:*}"
        PORT=0
        case $PROTO in
            rsync)
                $PORT=$RSYNC_PORT
                ;;
            https)
                $PORT=$HTTPS_PORT
                ;;
            http)
                $PORT=$HTTP_PORT
                ;;
            *)
                printf "[%(%F %T)T] Error: The remote path \"$s\" contains invalid protocol\n" -1 "$remote" >> 
                "${logpath}/$logfile" 2>&1
                ;;
        esac
        
        if [[nc -z $remote $PORTPORT 2>/dev/null]]; then
            $src=$remote
            break
        fi

        # If we get here the connection did not work
        printf "[%(%F %T)T] Warning: No connection with \"$s\", continuing with next...\n" -1 "$remote" >> 
                "${logpath}/$logfile" 2>&1

    done

    if [[! "$src"]]; then
        printf "[%(%F %T)T] Error: No connection with any source provided in\"$s\", cannot update this mirror\n" -1 
        "$file" >> "${logpath}/$logfile" 2>&1
        break
    fi

    if [[! "$filelistfile"]]; then
        printf "[%(%F %T)T] Info: No filelistfile is provided in \"$s\"\n" -1 "$file" >> "${logpath}/$logfile" 2>&1
    else
        checkresult=$(rsync --no-motd --dry-run --out-format="%n" "${src}/${filelistfile}" "${dst}/${filelistfile}")
    fi


done
exit 0

