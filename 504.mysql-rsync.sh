#!/bin/sh
#
# Shell script to run after mysql_backup to rsync the
# backups to a remote host.
# 
# Written by Geoff Garside <geoff.garside@m247.com>
# 

# Define these variables in either /etc/periodic.conf or
# /etc/periodic.conf.local to override the default values.
# 
# daily_mysql_backup_enable="YES" # do backups
# daily_mysql_rsync_enable="YES"  # rsync them
# daily_mysql_rsync_user="root"   # user to get keys from
# daily_mysql_rsync_ssh_args="ssh"
# daily_mysql_rsync_target="user@backups:mybackups"
# 

daily_mysql_rsync_user="root"

# Copy some vars in from /usr/local/etc/periodic/daily/503.mysql
daily_mysql_backupdir="/var/db/mysql/backups"

if [ -r /etc/defaults/periodic.conf ]; then
  . /etc/defaults/periodic.conf
  source_periodic_confs
fi

daily_mysql_rsync_flags="-tavz -e ${daily_mysql_rsync_ssh_args} --delete"

eval backupdir=${daily_mysql_backupdir}

rc=0

case "$daily_mysql_backup_enable" in
  [Yy][Ee][Ss])
    # OK backups are being taken, we can proceed.
    case "$daily_mysql_rsync_enable" in
      [Yy][Ee][Ss])
	# Even better, we want to rsync them too
	test "$(ls -A ${backupdir})" || exit $rc

	today=`date +"%Y-%m-%d %H:%M:%S"`
	echo "[$today]: $0 ran" >> /var/log/mysql-rsync.log

	echo "/usr/local/bin/rsync ${daily_mysql_rsync_flags} ${backupdir} ${daily_mysql_rsync_target}" >> /var/log/mysql-rsync.log
	su -l ${daily_mysql_rsync_user} -c "/usr/local/bin/rsync ${daily_mysql_rsync_flags} ${backupdir} ${daily_mysql_rsync_target}"

	[ $? -gt 0 ] && rc=3
      ;;
    esac
    ;;
esac

exit $rc
