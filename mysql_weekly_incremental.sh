#!/bin/env bash
# Author: Ben Vaughan -- 
#
# xtrabackup Documentation: https://www.percona.com/doc/percona-xtrabackup/LATEST/backup_scenarios/incremental_backup.html
# Assumption: xtrabackup >= 2.4 available
# Assumption: this script will be run as root
# Assumption: xtrabackup configuration is in /root/.my.cnf in the [xtrabackup] section
#
# Basic idea:
# Look through $BACKUPPATH for base backup, if none, do full backup, remove any incremental dirs, exit.
# Look through $BACKUPPATH for incremental backups. Compare last_lsn of base or last incremental
#      to from_lsn to "this" incremental. If lines up, then examine next incremental.
#      If doesn't match, then blow away "this" incremental and do another incremental 
#      with incremental-basedir set to last incremental dir.
#      If all LSN line up and no next incremental, increment incremental counter and run incremental backup.
# If this run was an base/full backup, copy base backup to $READYRESTOREPATH and do --prepare --apply-log-only
# If this run was an incremental backup, run --prepare --apply-log-only against $READYRESTOREPATH 

WHICH=/usr/bin/which
DATE=$(${WHICH} date)
XTRABACKUP=$(${WHICH} xtrabackup)
LS=$(${WHICH} ls)
GREP=$(${WHICH} grep)
AWK=$(${WHICH} awk)
RM=$(${WHICH} rm)
BASENAME=$(${WHICH} basename)
CP=$(${WHICH} cp)
FIND=$(${WHICH} find)
SORT=$(${WHICH} sort)
MKDIR=$(${WHICH} mkdir)

BACKUPPATH=/var/lib/mysql_backups
FULLBACKUPPATH=$BACKUPPATH/base
INCREMENTALPATH=$BACKUPPATH/incrementals
READYRESTOREPATH=$BACKUPPATH/readyrestore
CHECKPOINTFILE=xtrabackup_checkpoints
XTRALOG=/var/log/xtradump_backup.log

get_last_incremental_dir () {
  if [[ -z "$1" ]]; then
    return 1
  else
    INCREMENTDIR=$($BASENAME $1)
    LASTNUM=$(expr $INCREMENTDIR - 1)
    LASTDIR=$INCREMENTALPATH/$LASTNUM
    if [[ -d $LASTDIR ]]; then
      LASTINCREMENTAL=$LASTDIR
      return 0
    else
      LASTINCREMENTAL=$FULLBACKUPPATH
    fi
  fi
}

get_next_incremental_dir () {
  if [[ -z "$1" ]]; then
    return 1
  else
    INCREMENTDIR=$($BASENAME $1)
    NEXTNUM=$(expr $INCREMENTDIR + 1)
    NEXTINCREMENTAL=$INCREMENTALPATH/$NEXTNUM
  fi
}

if [[ -s $FULLBACKUPPATH/$CHECKPOINTFILE ]]; then
  # A full backup exists, so start grab last_lsn and check next incremental
  LAST_LSN=$($GREP to_lsn $FULLBACKUPPATH/$CHECKPOINTFILE | $AWK '{ print $3 }')
  
  # Find any incrementals in the $BACKUPPATH
  INCREMENTALDIRS=$($FIND "$INCREMENTALPATH" -maxdepth 1 -mindepth 1 -type d | $SORT -V)
  #echo "Incremental dirs: $INCREMENTALDIRS"
  if [[ -n $INCREMENTALDIRS ]]; then
    # There are incremental directories...
    for THISINCREMENTAL in $INCREMENTALDIRS; do
      #echo $THISINCREMENTAL
      if [[ -n $THISINCREMENTAL ]]; then
        INCR_START_LSN=$($GREP from_lsn $THISINCREMENTAL/$CHECKPOINTFILE | $AWK '{ print $3 }')
        echo "Found incremental starting at $INCR_START_LSN"
        if [[ $LAST_LSN == $INCR_START_LSN ]]; then
          # This incremental starts where the last left off, grab new LAST_LSN
          echo "Last incremental stopped at $LAST_LSN, this incremental starts at $INCR_START_LSN, checking next incremental..."
          LAST_LSN=$($GREP to_lsn $THISINCREMENTAL/$CHECKPOINTFILE | $AWK '{ print $3 }')
        else
          # THISINCREMENTAL is invalid. Delete and do a new incremental.
          echo "$THISINCREMENTAL is invalid, deleting and running a new incremental in its place"
          $RM -rf $THISINCREMENTAL
          # this should return $LASTINCREMENTAL
          get_last_incremental_dir "$THISINCREMENTAL"
          echo "Running incremental backup from $LASTINCREMENTAL to $THISINCREMENTAL"
          $XTRABACKUP --backup --target-dir=$THISINCREMENTAL --incremental-basedir=$LASTINCREMENTAL > $XTRALOG 2>&1
          if [ $? -eq 0 ]; then
            echo "New incremental backup successful. Attempting restore prep..."
            $XTRABACKUP --prepare --apply-log-only --target-dir=$READYRESTOREPATH --incremental-dir=$THISINCREMENTAL > $XTRALOG 2>&1
            if [ $? -eq 0 ]; then
              echo "New incremental restore prep successful."
              exit 0
            else
              echo "New incremental restore prep failed. Running new full backup."
              $RM -rf $FULLBACKUPPATH
              $RM -rf $INCREMENTALPATH
              $RM -rf $READYRESTOREPATH
              $MKDIR -p $INCREMENTALPATH
              $MKDIR -p $READYRESTOREPATH
              $XTRABACKUP --backup --target-dir=$FULLBACKUPPATH > $XTRALOG 2>&1
              if [ $? -eq 0 ]; then
                echo "Backup successful. Creating ready restore directory."
                $CP -r $FULLBACKUPPATH/* $READYRESTOREPATH/
                $XTRABACKUP --prepare --apply-log-only --target-dir=$READYRESTOREPATH > $XTRALOG 2>&1
                if [ $? -eq 0 ]; then
                  echo "Restore prep successful."
                else
                  echo "Restore prep failed."
                fi
              else
                echo "Backup failed."
                exit 1
              fi
            fi 
          else
            echo "New incremental backup failed."
            exit 1
          fi
        fi
      else
        echo "$THISINCREMENTAL was empty"
      fi
    done
    # If we made it here, then we need to run the next incremental in sequence 
    get_next_incremental_dir "$THISINCREMENTAL"
    echo "Running incremental backup from $THISINCREMENTAL to $NEXTINCREMENTAL" 
    $XTRABACKUP --backup --target-dir=$NEXTINCREMENTAL --incremental-basedir=$THISINCREMENTAL > $XTRALOG 2>&1
    if [ $? -eq 0 ]; then
      echo "Incremental backup successful. Running restore prep..."
      $XTRABACKUP --prepare --apply-log-only --target-dir=$READYRESTOREPATH --incremental-dir=$NEXTINCREMENTAL > $XTRALOG 2>&1
      if [ $? -eq 0 ]; then
        echo "Incremental restore prep successful."
      else
        echo "Incremental restore prep failed."
      fi
    else
      echo "Incremental backup failed."
    fi
  else
    # there is a full, but no incrementals, so make our first incremental
    echo "Running first incremental to $INCREMENTALPATH/1"
    $XTRABACKUP --backup --target-dir=$INCREMENTALPATH/1 --incremental-basedir=$FULLBACKUPPATH > $XTRALOG 2>&1
    if [ $? -eq 0 ]; then
      echo "First incremental backup successful. Running restore prep..."
      $XTRABACKUP --prepare --apply-log-only --target-dir=$READYRESTOREPATH --incremental-dir=$INCREMENTALPATH/1 > $XTRALOG 2>&1
      if [ $? -eq 0 ]; then
        echo "First incremental restore prep successful."
      else
        echo "First incremental restore prep failed."
      fi
    else
      echo "First incremental backup failed."
    fi
  fi
else
  # No base backup found, so do one.
  echo "No previous backup found. Creating new full backup."
  if [[ -d $BACKUPPATH ]]; then
    $RM -rf $FULLBACKUPPATH
    $RM -rf $INCREMENTALPATH
    $RM -rf $READYRESTOREPATH
    $MKDIR -p $INCREMENTALPATH
    $MKDIR -p $READYRESTOREPATH
    $XTRABACKUP --backup --target-dir=$FULLBACKUPPATH > $XTRALOG 2>&1
    if [ $? -eq 0 ]; then
      echo "Backup successful. Creating ready restore directory."
      $CP -r $FULLBACKUPPATH/* $READYRESTOREPATH/
      $XTRABACKUP --prepare --apply-log-only --target-dir=$READYRESTOREPATH > $XTRALOG 2>&1 
      if [ $? -eq 0 ]; then
        echo "Restore prep successful."
      else
        echo "Restore prep failed."
      fi
    else
      echo "Backup failed."
    fi
      
  else
    echo "$BACKUPPATH not found"
  fi
fi
