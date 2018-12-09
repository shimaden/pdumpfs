#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

MOUNTLABEL=backup
MOUNTPOINT=/backup
FILESYSTEM=ext4
MOUNTOPT="rw"

function mount()
{
  /bin/mount LABEL=${MOUNTLABEL} -t ${FILESYSTEM} -o ${MOUNTOPT} ${MOUNTPOINT}
}

function umount()
{
  /bin/umount $MOUNTPOINT
}


function usage()
{
  echo "${0} -m|-u"
}

if [ "$1" == "-m" ]; then # Mount
  mount
elif [ "$1" == "-u" ]; then # Unmount
  umount
else
  usage
fi
