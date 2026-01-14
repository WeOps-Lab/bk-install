#!/bin/bash
# Script Name: weops_settings_logs.sh
# Description: Script to configure weops logs clean settings
# Author: Jerko
# Created: 2023-04-02 18:19:13
# Version: 1.0
# Last Updated: 2023-04-02 18:19:13
# Change Log:
# - <update_time> <version_number> <update_description>
# - <update_time> <version_number> <update_description>
# ...
# Variables:
# - <variable_1>: variable description
# - <variable_2>: variable description
# ...

SELF_DIR=$(readlink -f "$(dirname "$0")")

# Define variables to store configuration settings
mongo_crond="30 00 * * *"
mysql_crond="30 00 * * *"
control_crond="30 00 * * *"
appo_crond="30 00 * * *"
appt_crond="30 00 * * *"

# Define variables to store log retention period in days
mysql_clean_binlog=7
rabbitmq_clean_log=15
control_clean_log=15
appo_clean_log=15
appt_clean_log=15
mongo_clean_log_days=15

# Define variable to store log retention period in hours for Kafka
kafka_clean_log='log.retention.hours=72'

source /data/install/utils.fc
# Function to remove existing cron jobs and add new ones
update_cron() {
  module=$1
  cmd=$2
  cron_schedule=$3
  /data/install/pcmd.sh -m $module "crontab -l | grep -v '$cmd' | crontab -"
  /data/install/pcmd.sh -m $module "echo '$cron_schedule $cmd' >> /var/spool/cron/root"
}

# mongodb
sed -i "s/days=15/days=$mongo_clean_log_days/" "${SELF_DIR}"/../clean_log_script/mongodb_clean_log.sh
scp "${SELF_DIR}"/../clean_log_script/mongodb_clean_log.sh $BK_MONGODB_IP:/data/
update_cron "mongodb" "/usr/bin/bash /data/mongodb_clean_log.sh" "$mongo_crond"

# mysql
scp "${SELF_DIR}"/../clean_log_script/mysql_clean* $BK_MYSQL_IP:/data/
update_cron "mysql" "/usr/bin/bash /data/mysql_clean_error_log.sh" "$mysql_crond"
update_cron "mysql" "/usr/bin/bash /data/mysql_clean_slow_log.sh" "$mysql_crond"

/data/install/pcmd.sh -m mysql "grep -q '^[^#]*expire_logs_days' /etc/mysql/default.my.cnf && sed -i '/^[^#]*expire_logs_days/ s/^expire_logs_days.*$/expire_logs_days = $mysql_clean_binlog/' /etc/mysql/default.my.cnf || echo 'expire_logs_days = $mysql_clean_binlog' >> /etc/mysql/default.my.cnf"

/data/install/pcmd.sh -m mysql "docker restart mysql"


# 中控机
cron_job_cmd="/usr/bin/find /data/bkce/logs/ -iname *.log* -type f -mtime +$control_clean_log -delete"
crontab -l | grep -v "${cron_job_cmd}" | crontab -
echo "$control_crond ${cron_job_cmd}" >> /var/spool/cron/root

if [ -n "$BK_APPO_IP" ];then
    appo_module="appo"
else
    appo_module="appt"
fi

if [ -n "$BK_APPT_IP" ];then
    appt_module="appt"
else
    appt_module="appo"
fi

# APPO
update_cron "${appo_module}" "/usr/bin/find /data/bkce/logs/ -iname *.log* -type f -mtime +$appo_clean_log -delete" "$appo_crond"
update_cron "${appo_module}" "/usr/bin/find /data/bkce/paas_agent/apps/logs/ -iname *.log* -type f -mtime +$appo_clean_log -delete" "$appo_crond"

# APPT
update_cron "${appt_module}" "/usr/bin/find /data/bkce/logs/ -iname *.log* -type f -mtime +$appt_clean_log -delete" "$appt_crond"

# rabbitmq
/data/install/pcmd.sh -m rabbitmq "sed -i 's%\\(/var/log/rabbitmq/\\)%/data/bkce/logs/rabbitmq/%g' /etc/logrotate.d/rabbitmq-server"
/data/install/pcmd.sh -m rabbitmq "sed -i '/^rotate\s*[0-9]\+/{s%rotate\s*[0-9]\+%rotate ${rabbitmq_clean_log}%}' /etc/logrotate.d/rabbitmq-server"

# kafka
/data/install/pcmd.sh -m kafka "if grep -q '^log.cleanup.policy=' /etc/kafka/server.properties; then sed -i 's/^log.cleanup.policy=.*/log.cleanup.policy=delete/' /etc/kafka/server.properties; else echo 'log.cleanup.policy=delete' >> /etc/kafka/server.properties; fi"

/data/install/pcmd.sh -m kafka "if grep -q '^log.retention.hours=' /etc/kafka/server.properties; then sed -i 's/^log.retention.hours=.*/${kafka_clean_log}/' /etc/kafka/server.properties; else echo '${kafka_clean_log}' >> /etc/kafka/server.properties; fi"

/data/install/pcmd.sh -m kafka "docker restart kafka"
