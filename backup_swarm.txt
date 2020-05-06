#!/bin/bash

SWARM_FILENAMESTRING="docker_swarm_backup"
DATESTRING=$(date +"%Y%m%d-%H%M%S")
HOSTNAME=$(hostname)
FILENAME="${SWARM_FILENAMESTRING}-${HOSTNAME}-${DATESTRING}.tgz"
BACKUP_PATH='/var/docker_backup/local'
ARCHIVE_PATH='/var/docker_backup/nfs'
MAX_AGELOCAL=7
MAX_AGEARCHIVE=90

# Test to see if this node is the leader
LEADER=$(docker node ls -f "role=manager" | tail -n+2 | grep -i leader | awk '{print $2}')
if [ "$LEADER" == '*' ]; then
    echo "This node is the Swarm Leader.  Backups will not be completed on this node."
    exit 0
fi

# Check to make sure there are enough managers available to run
REACHABLE=$(docker node ls -f "role=manager" |grep Reachable |wc -l)
if [ ${REACHABLE} -lt 2 ]; then
    echo "There are not enough available managers online"
    exit 0
fi

# Stop the Docker Engine
echo "Stopping Docker Engine"
systemctl stop docker
echo "Docker Engine is stopped"

# Backup the entire /var/lib/docker/swarm directory
echo "Beginning backup"
tar cvzf "${BACKUP_PATH}/${FILENAME}" /var/lib/docker/swarm
echo "Backup file written"

# Start the Docker Engine
echo "Starting Docker Engine"
systemctl start docker
echo "Docker Engine is running."

# Copy the Backup File into the Archive
if [ -f ${BACKUP_PATH}/${FILENAME} ]; then 
    cp ${BACKUP_PATH}/${FILENAME} ${ARCHIVE_PATH}
else
    echo "FATAL ERROR: Backup file was not found"
fi

# If the Swarm backup has been copied over, delete local backups older than MAX_AGELOCAL
# Also, delete archive backups older than MAX_AGEARCHIVE
if [ -f ${ARCHIVE_PATH}/${FILENAME} ]; then 
    echo "Deleting old local Swarm Backups"
    find ${BACKUP_PATH}/${SWARM_FILENAMESTRING}* -mtime +${MAX_AGELOCAL} -exec rm -f '{}' \;
    find ${ARCHIVE_PATH}/${SWARM_FILENAMESTRING}\-${HOSTNAME}* -mtime +${MAX_AGEARCHIVE} -exec rm -f '{}' \;
fi

echo "Backup is complete!"
echo "LocalFile:   ${BACKUP_PATH}/${SWARM_FILENAME}"
echo "ArchiveFile: ${ARCHIVE_PATH}/${SWARM_FILENAME}"