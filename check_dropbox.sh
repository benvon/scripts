#!/bin/bash

DBCONTROL=/usr/local/bin/dropbox.py
DATE=/bin/date
MKDIR=/bin/mkdir

TODAY=`$DATE --date=today +'%Y%m%d'`

now () { $DATE --date=today +'%Y%m%d %H:%M:%S -'; }

LOGPATH=${HOME}/log
LOGFILE=$LOGPATH/check_dropbox_$TODAY.log

if [ ! -d $LOGPATH ]; then
  $MKDIR -p $LOGPATH
fi

echo "$(now) Checking status of Dropbox on ${HOSTNAME} as ${USER}" >> $LOGFILE
$DBCONTROL running >> $LOGFILE 2>&1
DBSTATUS=$?
if [ $DBSTATUS -eq 0 ]; then
  echo "$(now) Restarting Dropbox..." >> $LOGFILE
  $DBCONTROL start >> $LOGFILE 2>&1
else
  echo "$(now) Dropbox running OK" >> $LOGFILE
fi
echo "$(now) Finished checking status of Dropbox" >> $LOGFILE
