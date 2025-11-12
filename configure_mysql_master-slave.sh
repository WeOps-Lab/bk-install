#!/bin/bash

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

source utils.fc

MASTER_HOST=$BK_MYSQL_MASTER_IP
MASTER_USER=$BK_MYSQL_ADMIN_USER
MASTER_PASSWORD=$BK_MYSQL_ADMIN_PASSWORD
SLAVE_HOST=${BK_MYSQL_SLAVE_IP[@]}
MASTER_LOG_FILE_1=$(./pcmd.sh -H $BK_MYSQL_MASTER_IP "mysql --login-path=default-root -e 'SHOW MASTER STATUS\G' | awk '/File:/ {print $2}'")
MASTER_LOG_FILE=$(echo $MASTER_LOG_FILE_1 | awk -F'File:' '{print $2}' | awk '{print $1}' | tr -d '[:space:]')
MASTER_LOG_POS_1=$(./pcmd.sh -H $BK_MYSQL_MASTER_IP "mysql --login-path=default-root -e 'SHOW MASTER STATUS\G' | awk '/Position:/ {print $2}'")
MASTER_LOG_POS=$(echo $MASTER_LOG_POS_1 | awk -F'Position:' '{print $2}' | awk '{print $1}' | tr -d '[:space:]')
GTID_MODE=$(./pcmd.sh -H $BK_MYSQL_MASTER_IP "mysql --login-path=default-root -e 'SHOW VARIABLES LIKE \"gtid_mode\"';" |grep gtid_mode| awk '{print $2}')

# 在主服务器上创建复制用户并授予适当的权限
./pcmd.sh -H $MASTER_HOST "mysql --login-path=default-root -e \"CREATE USER IF NOT EXISTS '$MASTER_USER'@'%' IDENTIFIED BY '$MASTER_PASSWORD';\""
./pcmd.sh -H $MASTER_HOST "mysql --login-path=default-root -e \"GRANT REPLICATION SLAVE ON *.* TO '$MASTER_USER'@'%';\""
./pcmd.sh -H $MASTER_HOST "mysql --login-path=default-root -e \"FLUSH PRIVILEGES;\""


# 在从服务器上设置主服务器的连接信息
for slave_ip in ${SLAVE_HOST[@]};do
	yellow_echo $slave_ip
	if [[ $GTID_MODE == "OFF" ]];then
                ./pcmd.sh -H $slave_ip "mysql --login-path=default-root -e \"CHANGE MASTER TO MASTER_HOST='$MASTER_HOST', MASTER_USER='$MASTER_USER', MASTER_PASSWORD='$MASTER_PASSWORD', MASTER_LOG_FILE='$MASTER_LOG_FILE', MASTER_LOG_POS=$MASTER_LOG_POS;\""
        else
        ./pcmd.sh -H $slave_ip "mysql --login-path=default-root -e \"CHANGE MASTER TO MASTER_HOST='$MASTER_HOST', MASTER_USER='$MASTER_USER', MASTER_PASSWORD='$MASTER_PASSWORD', MASTER_AUTO_POSITION=1\""
        fi
	./pcmd.sh -H $slave_ip "mysql --login-path=default-root -e \"START SLAVE;\""
        # 2024.4.2新增，部署主从遗留创建root的操作导致主从复制检查状态，一开始会提示检查错误
        ./pcmd.sh -H $slave_ip "mysql --login-path=default-root -e \"CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$BK_MYSQL_ADMIN_PASSWORD';\""
        ./pcmd.sh -H $slave_ip "mysql --login-path=default-root -e \"GRANT REPLICATION SLAVE ON *.* TO 'root'@'%';\""
        ./pcmd.sh -H $slave_ip "mysql --login-path=default-root -e \"FLUSH PRIVILEGES;\""
        # 对从机器配置只读，防止意外写入导致不同步
	./pcmd.sh -H $slave_ip "mysql --login-path=default-root -e \"SET GLOBAL read_only=ON;\""
        ./pcmd.sh -H $slave_ip "mysql --login-path=default-root -e \"SET GLOBAL super_read_only=ON;\""
	replication_status=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{print $2}')
	sql_running=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_SQL_Running:" | awk '{print $2}')
	if [[ "$replication_status" == "Yes" && "$sql_running" == "Yes" ]];then
		green_echo "$slave_ip{slave} -->> $MASTER_HOST{master} [SUCCESS] => 主从复制正常运行"
	else
		replicaiton_error=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Last_SQL_Error:" | awk '{print $2}')
		red_echo "$slave_ip{slave} -->> $MASTER_HOST{master} [FATL] => 主从复制未正常运行，请检查主从状态"
		red_echo "报错信息：$replicaiton_error"
	fi
done
