#!/bin/sh -
#
# $FreeBSD$
#
# Maintenance shell script to backup mysql databases
# Put this in /usr/local/etc/periodic/daily, and it will be run
# every night
#
# By Geoff Garside <Geoff.Garside at m247.com>, Mon, Jan 24 13:04:18 GMT 2010
#
# Inspired by postgresql port's backup script by
# Palle Girgensohn <girgen@pingpong.net>
#
# In public domain, do what you like with it,
# and use it at your own risk... :)
#

# Define these variables in either /etc/periodic.conf or
# /etc/periodic.conf.local to override the default values.
#
# ls / # do backup of all databases
# daily_mysql_backup_enable="foo bar db1 db2" # only do backup of a limited selection of databases
#
# Fine tune nightly backup you may use the following
#
# daily_mysql_host (str):			Set mysql host to connect to. Default "localhost".
# daily_mysql_user (str):			Set mysql user to login with. Default "root".
# daily_mysql_passwd (str):			Set mysql user password. Default blank.
# daily_mysql_backupdir (str):			Set directory to backup to. Default /var/db/mysql/backups.
# daily_mysql_savedays (str):			Number of days to keep backups. Default 7.
# daily_mysql_dumpargs (str):			Arguments to be passed to mysqldump. Default "--opt".
# daily_mysql_backup_bucket (str):		Name of the S3 bucket to upload to.
# daily_mysql_backup_ignore_system (str):	Ignore 'mysql', 'information_schema' and 'performance_schema'.

if [ -r /etc/defaults/periodic.conf ]
then
    . /etc/defaults/periodic.conf
    source_periodic_confs
fi

daily_mysql_backup_enable=${daily_mysql_backup_enable:-"NO"}
daily_mysql_host=${daily_mysql_host:-"localhost"}
daily_mysql_user=${daily_mysql_user:-"root"}
daily_mysql_passwd=${daily_mysql_passwd:-""}
daily_mysql_backupdir=${daily_mysql_backupdir:-"/var/db/mysql/backups"}
daily_mysql_savedays=${daily_mysql_savedays:-"7"}
daily_mysql_dumpargs=${daily_mysql_dumpargs:-"--opt"}
daily_mysql_backup_bucket=${daily_mysql_backup_bucket:-"NO"}
daily_mysql_backup_ignore_system=${daily_mysql_backup_ignore_system:-"YES"}

eval backupdir=${daily_mysql_backupdir}

daily_mysql_args=""
test -n "$daily_mysql_host" && daily_mysql_args="${daily_mysql_args}-h${daily_mysql_host} "
test -n "$daily_mysql_user" && daily_mysql_args="${daily_mysql_args}-u${daily_mysql_user} "
test -n "$daily_mysql_passwd" && daily_mysql_args="${daily_mysql_args}-p${daily_mysql_passwd} "

rc=0

mysql_backup() {
	# daily_mysql_backupdir must be writeable by user mysql
	# /var/db/mysql is just that under normal circumstances,
	# but this might not be where you want the backups...
	if [ ! -d ${backupdir} ] ; then
	    echo Creating ${backupdir}
	    mkdir -m 700 ${backupdir}; chown mysql ${backupdir}
	fi

	echo
	echo "MySQL backups"

	# Protect the data
	umask 077
	rc=$?
	now=`date +"%Y-%m-%dT%H:%M:%S"`

	db=$1
	while shift; do
		echo -n " $db"
		file=${daily_mysql_backupdir}/mysqldump_${db}_${now}
		su -l ${daily_mysql_user} -c "umask 077; mysqldump ${daily_mysql_dumpargs} ${daily_mysql_args} ${db} | gzip -9 > ${file}.gz"
		test $? -gt 0 && rc=3
		db=$1
	done

	if [ $rc -gt 0 ] ; then
		echo
		echo "Errors were reported during backup."
		return
	fi

	# sync to S3
	case "$daily_mysql_backup_bucket" in
		[Nn][Oo]|"")
			echo "No S3 bucket configured or disabled."
			rc=2
			;;
		*)
			aws s3 sync ${backupdir} s3://${daily_mysql_backup_bucket}
			;;
	esac


	# cleaning up old data
	find ${backupdir} -name 'mysqldump_*' \
		-a -mtime +${daily_mysql_savedays} -delete
	echo
}

case "$daily_mysql_backup_enable" in
	[Yy][Ee][Ss])
		show_query='SHOW DATABASES';

		case "$daily_mysql_backup_ignore_system" in
			[Yy][Es][Ss])
				show_query="${show_query} WHERE \`Database\` NOT IN (\"mysql\", \"information_schema\", \"performance_schema\")"
				;;
			[Nn][Oo])
				echo "This may require more invasive measures to stop all ops."
				;;
			*)
				echo "Misconfiguration in daily_mysql_backup_ignore_system"
				exit 2
				;;
		esac

		dbnames=""
		dbresults=`su -l ${daily_mysql_user} -c "umask 077; mysql ${daily_mysql_args} -e '${show_query}'"`
		for db in ${dbresults} ; do
			test "$db" = "Database" -o "$db" = "backups" && continue
			dbnames="${dbnames} ${db}"
		done
		mysql_backup $dbnames
		;;
	[Nn][Oo]|"")
		echo "Disabled"
		;;
	*)
		mysql_backup $daily_mysql_backup_enable
		;;
esac

exit $rc
