#!/bin/bash

DATE=/bin/date
TODAY=`$DATE --date=today +'%Y%m%d'`

RSYNC=/usr/bin/rsync

now () { $DATE --date=today +'%Y%m%d %H:%M:%S'; }


LOGDIR=$HOME/log
LOGFILE=$LOGDIR/sync_centos_$TODAY.log

if [ ! -d $LOGDIR ]; then
  mkdir -p $LOGDIR
fi

TARGETVERSIONS="6.5"
TARGETDIR=/misc/mirror/centos
#MIRRORSERVER=lug.mtu.edu
#MIRRORSERVER=bay.uchicago.edu
MIRRORSERVER=mirror.anl.gov
MIRRORPATH=centos
#MIRRORPATH=CentOS

if [ -d $TARGETDIR ] ; then
    for VERSION in $TARGETVERSIONS; do
      echo "$(now) - starting rsync for version $VERSION" >> $LOGFILE
      $RSYNC  -klavSHP --delete --exclude "local*" $MIRRORSERVER::$MIRRORPATH/$VERSION/ $TARGETDIR/$VERSION >> $LOGFILE 2>&1
      echo "$(now) - rsync finished for version $VERSION" >> $LOGFILE
    done
else
    echo "$(now) - Target directory $TARGETDIR not present." >> $LOGFILE
fi
