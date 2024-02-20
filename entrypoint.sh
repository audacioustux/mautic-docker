#!/bin/bash

set -eax

############################################

# wait untill the db is fully up before proceeding
wait-for-db(){
	echo -n "Waiting for database connection..."
	while ! mysqladmin --host="$MYSQL_HOST" --port=$MYSQL_PORT --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" ping --silent &> /dev/null; do
		echo -n "."
		sleep 5
	done
}

"wait-for-db"

# generate a local config file if it doesn't exist.
# This is needed to ensure the db credentials can be prefilled in the UI, as env vars aren't taken into account.
if [ ! -f /var/www/html/config/local.php ]; then

	su -s /bin/bash www-data -c 'touch /var/www/html/config/local.php'

	cat <<'EOF' > /var/www/html/config/local.php
<?php
$parameters = array(
	'db_driver' => 'pdo_mysql',
	'db_host' => getenv('MYSQL_HOST'),
	'db_port' => getenv('MYSQL_PORT'),
	'db_name' => getenv('MAUTIC_DB_NAME'),
	'db_user' => getenv('MYSQL_USER'),
	'db_password' => getenv('MYSQL_PASSWORD'),
	'db_table_prefix' => null,
	'db_backup_tables' => 1,
	'db_backup_prefix' => 'bak_',
);
EOF
fi

############################################

mkdir -p /opt/mautic/cron

if [ ! -f /opt/mautic/cron/mautic ]; then

	cat <<EOF > /opt/mautic/cron/mautic
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
BASH_ENV=/tmp/cron.env

* * * * * php /var/www/html/bin/console mautic:segments:update 2>&1 | tee /tmp/cron.log
* * * * * php /var/www/html/bin/console mautic:campaigns:update 2>&1 | tee /tmp/cron.log
* * * * * php /var/www/html/bin/console mautic:campaigns:trigger 2>&1 | tee /tmp/cron.log
* * * * * php /var/www/html/bin/console mautic:import --limit 50 2>&1 | tee /tmp/cron.log
EOF
fi

# register the crontab file for the www-data user
crontab -u www-data /opt/mautic/cron/mautic

# create the fifo file to be able to redirect cron output for non-root users
mkfifo /tmp/cron.log | true
chmod 777 /tmp/cron.log

# ensure the PHP env vars are present during cronjobs
declare -p | grep 'PHP_INI_VALUE_' > /tmp/cron.env

############################################

wait-for-mautic(){
	# wait until Mautic is installed
	echo -n "Mautic not installed yet, waiting..."
	until php -r 'file_exists("/var/www/html/config/local.php") ? include("/var/www/html/config/local.php") : exit(1); exit(isset($parameters["site_url"]) ? 0 : 1);'; do
		echo -n "."
		sleep 5
	done
}

web-server(){
	apache2-foreground
}

cron-jobs(){
	cron -f | tail -f /tmp/cron.log
}

worker(){
	supervisord -c /etc/supervisor/conf.d/supervisord.conf
}

# run all the services in parallel
parallel --halt now,fail=1 --linebuffer -j0 ::: 'web-server' 'wait-for-mautic && cron-jobs' 'wait-for-mautic && worker'
