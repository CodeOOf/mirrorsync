# Mirrorsync
**A repository mirroring tool by CodeOOf**

# Introduction
Mirrorsync by CodeOOf is a mirroring tool for synchronizing multiple 
repositories over the network to local storage. The main purpose is to keep a 
local mirror server that can handle multiple sources and alternative sources if 
one is down. The main script can be set up using cron or just manual calls. 

## Features 
Currently the script has these features:
* Many validation steps with detailed log to ensure stability and control
* Ability to synchronize multiple repositories against a single local path
* Able to define multiple remotes in case of connection error
* Manage version exclusion at source to minimize local footprint
* Define custom exclusion queries for each repository
* Verifies diskspace before starting transfer
* Log file generated specific for each synchronization change

**Protocols that the script currently has support for is:**
* rsync
* http/https

The script uses a custom function called httpsync that scrapes a remote 
http/https website with the help of curl. The data is then compared with the 
local files and downloaded as needed, like the rsync function.

## Installation
Required packets used with this script, ensure that these are available before 
using the script:
* rsync
* curl 

Also read the [Disclaimer](#disclaimer).

Installation can be done via the installation script or by using the 
[Manual](#manual) steps below. Download this repository and from the root run 
the following command:
```
./install.sh --user <service_user>

For example, a default installation:
./install.sh /opt/mirrorsync mirrorsa
```
Then update the configurations found at ```/etc/mirrorsync/```.

### Manual
This installation shows how this can be done as root with a local service 
account as end user.

The default file structure is seen bellow.  
The ```[XXX]``` markings to the right of a file or directory indicates the 
required permissions for the user or service account that will run the scripts. 
```bash
├── etc
│   └── mirrorsync
│       ├── repos.conf.d [r+x]
│       │   ├── repo1.conf [r]
│       │   └── repo2.conf [r]
│       └── mirrorsync.conf [r]
├── opt
│   └── mirrorsync [r+w]
│       ├── excludes [r+w]
│       │   ├── httpsync.sh.lockfile
│       │   ├── repo1_exclude.txt
│       │   └── repo2_exclude.txt
│       ├── .version [r]
│       ├── httpsync.sh [r+x]
│       └── mirrorsync.sh [r+x]
├── var
│   └── log
│       └── mirrorsync [r+w]
│           ├── 2XYYZZHHMM_repo1_rsyncupdate.log
│           ├── 2XYYZZHHMM_repo2_httpsupdate.log
│           └── mirrorsync.log
└── ex. data/mirrors [r+w]
    └── example_mirror
        └── synced files...
```
Based on the above file structure the following terms will be used:
```
config_path=/etc/mirrorsync
installation_path=/opt/mirrorsync
exclude_path=/opt/mirrorsync/excludes
```

1. Download this repo
2. Create the directories for ```config_path, installation_path``` and 
```exclude_path```
    > Ensure that the thought out user or service account using this script can 
    > read in ```config_path``` and read+execute in ```installation_path``` and 
    > read+write in ```exclude_path```
3. Copy the content from this repo ```etc/mirrorsync``` into the created 
```config_path```
4. Copy the content from this repo ```opt/mirrorsync``` into the created 
```installation_path```
5. Update the files inside the ```config_path``` and create new mirrors based 
on the ```example.conf``` found in ```repo.conf.d```
6. Update permissions for intended script user and set up a data directory for 
the mirrors as defined in ```<config_path>/mirrorsync.conf```
7. Set up a cron job with the script according to ```example.crontab``` or just 
runt the script manually

Example setting up the crontab for another user:
```
sudo crontab -u mirrorsa -e
```
Then just follow the examples from ```example.crontab```

### Periodic Synchronization
Add the script to crontab, see ```example.crontab``` in root of this repository.

## Update
To perform update, download/update this repository and from the root run:
```
Default installation:
./update.sh

Root user updating default installation for a specific service account:
sudo bash ./update.sh --user mirrorsa --group root
```

## Remove
If you wish to remove the script just run the uninstall script:
```
./uninstall.sh
```
> **WARNING** Use the **EXACT** same arguments as when installing except for 
> user and groups if **not** using default paths.

## Disclaimer
The goal of the script development is to use as little  3rd party tools as 
possible and might therefor not have the best solutions. The script is also 
being developed using Rocky Linux 9+ as the baseline for testing, there is a 
high chance for success using any of the RHEL family origins but no guarantee 
for other distros at the moment.

## Credits
This script was inspired by:
* Mirrorsync from [rocky-tools](https://github.com/rocky-linux/rocky-tools)

## License
Copyright &copy; 2024 CodeOOf

