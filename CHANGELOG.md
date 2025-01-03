# Changelog

## Pre-Release 1.0.1-beta (1 January, 2025)
* Files are added with the remote modification date, see #2
* Adding directory and file permission on every synced file and path with 
option to use custom, see #4
* Minor general bug fixes like syntax errors
* Bugfixes: #5

## Pre-Release 1.0.0-beta (30 December, 2024)
* Minor bug fixes
* Moved the lockfile creation to the exclude folder to avoid write premission 
in script path
* Added read check on repository configuration file
* Added changelog printout to update script
* Minor fixes to texts in both readme and printouts

## Pre-Release 1.0.0-alpha (29 Decemeber, 2024)
* Updated a comprehensive readme
* Created a uninstall script: uninstall.sh
* Created an installation script: install.sh
* Added a progress bar for the main script
* Created comprehensive logging ability to the scripts
* Debug mode added for both mirrorsync.sh and httpsync.sh
* Added Arguments parser to every script
* Created a update script: update.sh
* Created a custom HTTP/HTTPS Synchronization script using curl with commands in 
similarity with rsync
* The main script now handles both rsync and http/https repositories
* The main script handles multiple failover remote sources for each mirror
* The main script handles multiple mirrors
* Created the main script: mirrorsync.sh