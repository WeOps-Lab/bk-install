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

green_echo " 1、主从切换脚本需要在中控机的install目录下执行，执行方法./mysql_master-slave_switching.sh ip（需要切换成新master的slaveip）\n 2、执行主从切换脚本期间会短时间执行锁库，只能读不能写，执行完后解锁。\n 3、执行完主从切换脚本，会自动修改对应的consul解析。\n 4、执行完主从切换脚本，会自动修改中控机对应的mysql --login。 \n 5、执行完主从切换脚本，会自动修改install.config的对应mysql的主从角色并同步到所有主机。"

SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/load_env.sh
source "${SELF_DIR}"/initdata.sh
source "${SELF_DIR}"/tools.sh
source "${SELF_DIR}"/utils.fc

set -e

source <(/opt/py36/bin/python ${SELF_DIR}/qq.py  -s -P ${SELF_DIR}/bin/default/port.yaml)
projects=${_projects["mysql"]}

slave_ip=$1
master_ip=`dig mysql-default.service.consul | grep "mysql-default.service.consul. 0" | awk '{print $NF}' | tr -d '[:space:]'`
mysql_slave_ips=`cat "${SELF_DIR}"/bin/02-dynamic/hosts.env | grep -i mysql|grep -i slave |grep -i ip| grep -v "$slave_ip" | awk -F"'" '{print $2}'`

MASTER_HOST=$slave_ip
MASTER_USER=$BK_MYSQL_ADMIN_USER
MASTER_PASSWORD=$BK_MYSQL_ADMIN_PASSWORD
SLAVE_HOST=($master_ip $mysql_slave_ips)
MASTER_LOG_FILE_1=$(./pcmd.sh -H $MASTER_HOST "mysql --login-path=default-root -e 'SHOW MASTER STATUS\G' | awk '/File:/ {print $2}'")
MASTER_LOG_FILE=$(echo $MASTER_LOG_FILE_1 | awk -F'File:' '{print $2}' | tr -d '[:space:]')
MASTER_LOG_POS_1=$(./pcmd.sh -H $MASTER_HOST "mysql --login-path=default-root -e 'SHOW MASTER STATUS\G' | awk '/Position:/ {print $2}'")
MASTER_LOG_POS=$(echo $MASTER_LOG_POS_1 | awk -F'Position:' '{print $2}' | tr -d '[:space:]')

if [ -n "$master_ip" ];then
        if [ -n "$slave_ip" ];then
                replication_status=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{print $2}')
                if [ "$replication_status" == "Yes" ];then
                        green_echo "$slave_ip{slave} -->> $master_ip{master} [SUCCESS] => 主从状态正常运行，进行主从切换"
                        mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $master_ip -P $BK_PAAS_MYSQL_PORT -e "FLUSH TABLES WITH READ LOCK;"
                        mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "stop slave;"
                        # 取消原master的consul解析
                        ./pcmd.sh -H $master_ip "mkdir -p /tmp/backup/mysql_consul_$(date +%F)"
                        ./pcmd.sh -H $master_ip "mv -f /etc/consul.d/service/mysql*.json /tmp/backup/mysql_consul_$(date +%F)/"
                        ./pcmd.sh -H $master_ip "consul reload"
                        # 添加新master的consul解析
                        for module in $projects;do
                                ./pcmd.sh -H $slave_ip "install -d /etc/consul.d/service/; ${SELF_DIR}/bin/reg_consul_svc -n "${_project_consul["mysql,$module"]}" -p $BK_PAAS_MYSQL_PORT -a $slave_ip -D >>/etc/consul.d/service/mysql-$module.json"
                        done
                        ./pcmd.sh -H $slave_ip "install -d /etc/consul.d/service/; ${SELF_DIR}/bin/reg_consul_svc -n "${_project_consul["mysql,default"]}" -p "$BK_PAAS_MYSQL_PORT" -a $slave_ip -D >>/etc/consul.d/service/mysql-default.json"
                        ./pcmd.sh -H $slave_ip "consul reload"
                        # 解锁旧的master库
                        mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $master_ip -P $BK_PAAS_MYSQL_PORT -e "UNLOCK TABLES;"
                        # 配置新的mysql主从
                        for ip in "${SLAVE_HOST[@]}";do
                                ./pcmd.sh -H $ip "mysql --login-path=default-root -e \"STOP SLAVE;\""
                                ./pcmd.sh -H $ip "mysql --login-path=default-root -e \"RESET SLAVE ALL;\""
                                ./pcmd.sh -H $ip "mysql --login-path=default-root -e \"CHANGE MASTER TO MASTER_HOST='$MASTER_HOST', MASTER_USER='$MASTER_USER', MASTER_PASSWORD='$MASTER_PASSWORD', MASTER_LOG_FILE='$MASTER_LOG_FILE', MASTER_LOG_POS=$MASTER_LOG_POS;\""
                                ./pcmd.sh -H $ip "mysql --login-path=default-root -e \"START SLAVE;\""
                                replication_status=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{print $2}')
                                if [ "$replication_status" == "Yes" ];then
                                        green_echo "$ip{slave} -->> $slave_ip{master} [SUCCESS] => 新的主从配置成功,状态为Yes."
                                else
                                        replicaiton_error=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Last_SQL_Error:" | awk '{print $2}')
                                        red_echo "$ip{slave} -->> $slave_ip{master} [FAIL] => 新的主从状态检查不通过,请手动检查报错."
                                        red_echo "报错信息：$replicaiton_error"
                                fi
                        done
                                        # 修改中控机install.config,并同步到其他机器
                        sed -i "/$master_ip/s/mysql(master)/mysql(slave)/g" install.config
                        sed -i "/$slave_ip/s/mysql(slave)/mysql(master)/g" install.config
                        ./bkcli install bkenv
                        ./bkcli sync common
                        # 修改中控机的mysql --login配置
                        mkdir -p /tmp/backup/mysql_login_$(date +%F)
                        mv -f /root/.mylogin.cnf /tmp/backup/mysql_login_$(date +%F)
                        for project in ${projects[@]}; do
                                ./bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,${project}"]}" -h "$slave_ip" -u "root" -p "$BK_MYSQL_ADMIN_PASSWORD"
                        done
                        ./bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,default"]}" -h "$slave_ip" -u "root" -p "$BK_MYSQL_ADMIN_PASSWORD"
                        if lsof -i:$BK_PAAS_MYSQL_PORT -sTCP:LISTEN 1>/dev/null 2>&1;then
                                ./bin/setup_mysql_loginpath.sh -n 'default-root' -h '/var/run/mysql/default.mysql.socket' -u 'root' -p "$BK_MYSQL_ADMIN_PASSWORD"
                        fi 
                else
                        replicaiton_error=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Last_SQL_Error:" | awk '{print $2}')
                        red_echo "$slave_ip{slave} -->> $master_ip{master} [FAIL] => 主从状态未正常运行，请检查"
                        red_echo "报错信息：$replicaiton_error"
                        exit 1
                fi
        else
                red_echo "[FAIL] => 请输入要切换的slave ip. 例: ./mysql_master-slave_switching.sh 10.10.10.11"
                exit 1
        fi
else
        red_echo "[FAIL] => mysql-default.service.consul 解析不出ip,请检查"
        exit 1
fi