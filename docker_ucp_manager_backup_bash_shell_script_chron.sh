#!/bin/bash
UCP_VERSION=$(docker inspect --format='{{ index .Config.Labels "com.docker.ucp.version"}}' ucp-controller)
UCP_FILENAMESTRING="docker_ucp_backup"
DTR_FILENAMESTRING="docker_dtr_backup"
DATESTRING=$(date +"%Y%m%d-%H%M%S")
HOSTNAME=$(hostname)
################################################################################
# Build filenames for UCP
UCP_FILENAMENOEXT="${UCP_FILENAMESTRING}-${HOSTNAME}-${DATESTRING}"
UCP_FILENAME=${UCP_FILENAMENOEXT}.tar
# Do the same thing with DTR
DTR_FILENAMENOEXT="${DTR_FILENAMESTRING}-${HOSTNAME}-${DATESTRING}"
DTR_FILENAME=${DTR_FILENAMENOEXT}.tar
################################################################################
PASSFILE='/root/.docker_backuprc'
BACKUP_PATH='/var/docker_backup/local'
ARCHIVE_PATH='/var/docker_backup/nfs'
MAX_AGELOCAL=7
MAX_AGEARCHIVE=90
PERMSSET=777
PERMSREVERT=755

# Test local backup path and create if needed
if [ ! -d ${BACKUP_PATH} ]; then 
    mkdir ${BACKUP_PATH} 
fi

# Read in our configuration items from a config file here
# Get the values for the ENCRYPT_PASS as well as DTR_USERNAME/DTR_PASSWORD out of this file
if [ -f ${PASSFILE} ]; then 
    # Get ENCRYPT_PASS
    # Get the UCP_URL
    # Get DTR_USERNAME HERE
    # Get DTR_PASSWORD HERE
    # Get the DTR_REPLICA_ID here
    source ${PASSFILE}
else
    echo "FATAL ERROR: Password file not found at: ${PASSFILE}"
    exit 1
fi

# Set global write permissions to backup location (docker backup requirement)
chmod ${PERMSSET} ${BACKUP_PATH}

# Do the backup of UCP
docker container run \
    --rm \
    --log-driver none \
    --name ucp \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume ${BACKUP_PATH}:/backup \
    docker/ucp:${UCP_VERSION} backup \
    --file ${UCP_FILENAME} \
    --passphrase "${ENCRYPT_PASS}" \
    --include-logs false

# Do the backup of DTR
docker container run \
    --rm \
    --interactive \
    --log-driver none \
    docker/dtr:${DTR_VERSION} backup \
    --ucp-url ${UCP_URL} \
    --ucp-insecure-tls \
    --ucp-username ${DTR_USERNAME} \
    --ucp-password ${DTR_PASSWORD} \
    --existing-replica-id ${DTR_REPLICA_ID} > \
    "${BACKUP_PATH}/${DTR_FILENAME}"

# Let's move the backups to  the archive
# Test backup exists and if so copy it to archive
for X in [${UCP_FILENAME},${DTR_FILENAME}]; do
    if [ -f ${BACKUP_PATH}/${X} ]; then 
        if [ $X = ${UCP_FILENAME} ]; then
            cp ${BACKUP_PATH}/${UCP_FILENAMENOEXT}* ${ARCHIVE_PATH}
        else
            cp ${BACKUP_PATH}/${DTR_FILENAMENOEXT}* ${ARCHIVE_PATH}
        fi
    else
        echo "FATAL ERROR: Backup did not complete"
    fi
done

# If the UCP backup has been copied over, delete local backups older than max days
if [ -f ${ARCHIVE_PATH}/${UCP_FILENAME} ]; then 
    echo "Deleting old local UCP Backups"
    find ${BACKUP_PATH}/${UCP_FILENAMESTRING}* -mtime +${MAX_AGELOCAL} -exec rm -f '{}' \;
    find ${ARCHIVE_PATH}/${UCP_FILENAMESTRING}\-${HOSTNAME}* -mtime +${MAX_AGEARCHIVE} -exec rm -f '{}' \;
fi

# If the DTR backup has been copied over, delete local backups older than max days
if [ -f ${ARCHIVE_PATH}/${DTR_FILENAME} ]; then 
    echo "Deleting old local DTR Backups"
    find ${BACKUP_PATH}/${DTR_FILENAMESTRING}* -mtime +${MAX_AGELOCAL} -exec rm -f '{}' \;
    find ${ARCHIVE_PATH}/${DTR_FILENAMESTRING}\-${HOSTNAME}* -mtime +${MAX_AGEARCHIVE} -exec rm -f '{}' \;
fi

chmod ${PERMSREVERT} ${BACKUP_PATH}
