#!/bin/bash
source utils.fc

red_echo ()      { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[031;1m$@\033[0m"; }
green_echo ()    { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[032;1m$@\033[0m"; }
yellow_echo ()   { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[033;1m$@\033[0m"; }
blue_echo ()     { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[034;1m$@\033[0m"; }
purple_echo ()   { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[035;1m$@\033[0m"; }
bred_echo ()     { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[041;1m$@\033[0m"; }
bgreen_echo ()   { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[042;1m$@\033[0m"; }
byellow_echo ()  { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[043;1m$@\033[0m"; }
bblue_echo ()    { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[044;1m$@\033[0m"; }
bpurple_echo ()  { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[045;1m$@\033[0m"; }
bgreen_echo ()   { [ "$HASTTY" == 0 ] && echo "$@" || echo -e "\033[042;34;1m$@\033[0m"; }

slave_ip=$(cat install.config | grep "mysql(slave)" |grep -v '#' | awk '{print $1}')
master_ip=$(cat install.config | grep "mysql(master)"|grep -v '#' | awk '{print $1}')

check_replication() {
        for ip in ${slave_ip[@]};do
                replication_status=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{print $2}')
                sql_running=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_SQL_Running:" | awk '{print $2}')
                if [[ "$replication_status" == "Yes" && "$sql_running" == "Yes" ]];then
                        green_echo "$ip{slave} -->> $master_ip{master} [SUCCESS] => 主从复制正常运行"
                else
                        red_echo "$ip{slave} -->> $master_ip{master} [FATL] => 主从复制未正常运行，请检查主从状态"
                        replicaiton_error=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Last_SQL_Error:")
                        red_echo "报错信息: $replicaiton_error"
                fi
        done
}

check_replication
