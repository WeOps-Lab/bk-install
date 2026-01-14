#!/bin/bash
# Script Name: weops_settings_dbbackup.sh
# Description: Script to configure dbbackup init
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

function dbbackup_init() {
    local db_type="$1"
    /data/install/pcmd.sh -m "$db_type" "/data/install/storage/dbbackup/dbbackup_init.sh blueking $db_type"
}

if [[ -z "$1" ]]; then
    echo "Please specify a backup type: all, mysql, mongodb, or redis"
    exit 1
fi

# 根据输入参数选择备份类型
case "$1" in
    all)
        dbbackup_init mysql
        dbbackup_init mongodb
        dbbackup_init redis
        ;;
    mysql)
        dbbackup_init mysql
        ;;
    mongodb)
        dbbackup_init mongodb
        ;;
    redis)
        dbbackup_init redis
        ;;
    *)
        echo "Invalid input: $1. Please specify a backup type: all, mysql, mongodb, or redis"
        exit 1
        ;;
esac

exit 0
