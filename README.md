# Mirrorsync
<center><b>A repository mirroring tool by CodeOOf</b></center>

# Introduction
Mirrorsync by CodeOOf is a mirroring tool for synchronizing multiple 
repositories over the network to local storage. The main purpose is to keep a 
local mirror server that can handle multiple sources and alternative sources if 
one is down. The main script can be set up using chrone or just manual calls. 

## Features 
Currently the script has these features:
* Many validation steps with detailed log to ensure stability and control
* Ability to syncronize multiple repositories against a single local path
* Able to define multiple remotes in case of connection error
* Mangage version exclusion at source to minimize local footprint
* Define custom exclusion queries for each repository
* Verifies diskspace before starting transfer
* Specific update log for each run

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
./install.sh <installation_path> <service_user>

For example a default installation:
./install.sh /opt/mirrorsync mirrorsa
```
Then update the configurations found at ```/etc/mirrorsync/```.

### Manual
This installation shows how this can be done as root with a local service 
account as end user.

The default file structure that these instructions will lead to:
```bash
├── etc
│   └── mirrorsync [r]
│       ├── repos.conf.d
│       │   ├── repo1.conf
│       │   └── repo2.conf
│       └── mirrorsync.conf
├── opt
│   └── mirrorsync
│       ├── excludes [r+w]
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
The intended file structure, the ```[XXX]``` markings to the right of a file or 
directory indicates the required permissions for the user or service account 
that will run the scripts.  
Based on the above file structure the following terms will be used:
```
config_path=/etc/mirrorsync
installation_path=/opt/mirrorsync
exclude_path=/opt/mirrorsync/excludes
```
> **WARNING!**  
> The ```config_path``` is defined hard in the script and requires manual 
> update by a daring admin each time the update script is used. Not 
> recommended for the lazy user.

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
runt the script manualy

### Periodic Syncronization
Add the script to crontab, see ```example.crontab``` in root of this repository.

## Update
To perform update, download/update this repository and from the root run:
```
Default installation:
./update.sh

Root user updating default installation for a specific service account:
sudo bash ./update.sh --user mirrorsa --group root
```

## Disclaimer
The goal of the script development is to use as litle 3rd party tools as 
possible and might therefor not have the best solutions. The script is also 
being developed using Rocky Linux 9+ as the baseline for testing, there is a 
high chance for success using any of the RHEL family origins but no garantee for 
other distros at the moment.

## Credits
This script was inspired by:
* Mirrorsync from [rocky-tools](https://github.com/rocky-linux/rocky-tools)

## License
Copyright &copy; 2024 CodeOOf

