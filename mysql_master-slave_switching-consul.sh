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

yellow_echo "************************** 注意 ******************************************"
yellow_echo "** 该脚本是用于 MySQL consul解析一键切换。                              **"
yellow_echo "** 主MySQL 切换至从 MySQL 。                                            **"
yellow_echo "** 主从切换脚本需要在中控机的install目录下执行                          **"
yellow_echo "** 执行完主从切换脚本，会自动修改对应的consul解析                       **"
yellow_echo "** 执行完主从切换脚本，会自动修改中控机对应的mysql --login快捷登录      **"
yellow_echo "** 执行完主从切换脚本，会自动修改对应的consul解析                       **"
yellow_echo "** 执行完主从切换脚本，会自动修改install.config的对应mysql的主从角色    **"
yellow_echo "** 并同步到所有主机。                                                   **"
yellow_echo "**************************************************************************"

SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/load_env.sh
source "${SELF_DIR}"/initdata.sh
source "${SELF_DIR}"/tools.sh
source "${SELF_DIR}"/utils.fc

set -e

yellow_echo "角色分配如下"
echo "$(cat install.config |grep  'mysql')"

source <(/opt/py36/bin/python ${SELF_DIR}/qq.py  -s -P ${SELF_DIR}/bin/default/port.yaml)
projects=${_projects["mysql"]}

#master_ip=`dig mysql-default.service.consul | grep "mysql-default.service.consul. 0" | awk '{print $NF}' | tr -d '[:space:]'`
step "此脚本需在中控机执行,请输入主节点信息"

green_echo "请输入切换前 MySQL 的 Master IP，一般填写mysql(master)的IP:"
read -p "" master_ip

if [ "$master_ip" == "" ];
then
    fail "输入的参数不正确"
fi

green_echo "请输入要切换后的 MySQL 的Master IP:"
read -p "" slave_ip

if [ "$slave_ip" == "" ];
then
    fail "输入的参数不正确"
fi
master_ip=$master_ip
#mysql_slave_ips=`cat "${SELF_DIR}"/bin/02-dynamic/hosts.env | grep -i mysql|grep -i slave |grep -i ip| grep -v "$slave_ip" | awk -F"'" '{print $2}'`

MASTER_HOST=$slave_ip
MASTER_USER=$BK_MYSQL_ADMIN_USER
MASTER_PASSWORD=$BK_MYSQL_ADMIN_PASSWORD
CONTROLLER_IP=$(cat "${SELF_DIR}"/.controller_ip)

#SLAVE_HOST=($master_ip $mysql_slave_ips)
#MASTER_LOG_FILE_1=$(./pcmd.sh -H $MASTER_HOST "mysql --login-path=default-root -e 'SHOW MASTER STATUS\G' | awk '/File:/ {print $2}'")
#MASTER_LOG_FILE=$(echo $MASTER_LOG_FILE_1 | awk -F'File:' '{print $2}' | tr -d '[:space:]')
#MASTER_LOG_POS_1=$(./pcmd.sh -H $MASTER_HOST "mysql --login-path=default-root -e 'SHOW MASTER STATUS\G' | awk '/Position:/ {print $2}'")
#MASTER_LOG_POS=$(echo $MASTER_LOG_POS_1 | awk -F'Position:' '{print $2}' | tr -d '[:space:]')

if [ -n "$master_ip" ];then
	if [ -n "$slave_ip" ];then
		#replication_status=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{print $2}')
		#sql_running=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_SQL_Running:" | awk '{print $2}')
                # 取消主从复制鉴定，因为可能只剩下一台从的情况
                #if [[ "$replication_status" == "Yes" && "$sql_running" == "Yes" ]];then
                        #green_echo "$slave_ip{slave} -->> $master_ip{master} [SUCCESS] => 主从状态正常运行，进行取消原master的consul解析"
			#mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $master_ip -P $BK_PAAS_MYSQL_PORT -e "FLUSH TABLES WITH READ LOCK;"
			#mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "stop slave;"
			# 取消原master的consul解析
                        yellow_echo "在$master_ip移除consul解析,备份至/tmp/backup/mysql_consul_$(date +%F)/"
			# 新增m如果master是宕机的情况，无法连通导致脚本异常退出
		        if ssh "$master_ip" 'date -R' > /dev/null 2>&1;then
                	./pcmd.sh -H $master_ip "if [[ ! -d /tmp/backup/mysql_consul_$(date +%F) ]];then mkdir -p /tmp/backup/mysql_consul_$(date +%F);fi"
                	./pcmd.sh -H $master_ip "if [[ -f /etc/consul.d/service/mysql-default.json ]];then mv -f /etc/consul.d/service/mysql*.json /tmp/backup/mysql_consul_$(date +%F)/;fi"
                	./pcmd.sh -H $master_ip "consul reload"|| echo "consul reload failed"
			fi
                        # 添加新master的consul解析
			for module in $projects;do
                                yellow_echo "在$slave_ip 执行/etc/consul.d/service/mysql-$module.json的写入"
                        	./pcmd.sh -H $slave_ip "if [[ ! -f /etc/consul.d/service/mysql-$module.json ]];then install -d /etc/consul.d/service/; ${SELF_DIR}/bin/reg_consul_svc -n "${_project_consul["mysql,$module"]}" -p $BK_PAAS_MYSQL_PORT -a $slave_ip -D >>/etc/consul.d/service/mysql-$module.json;fi"
                	done
                         yellow_echo "在$slave_ip 执行/etc/consul.d/service/mysql-default.json的写入"
			./pcmd.sh -H $slave_ip "if [[ ! -f /etc/consul.d/service/mysql-default.json ]];then install -d /etc/consul.d/service/; ${SELF_DIR}/bin/reg_consul_svc -n "${_project_consul["mysql,default"]}" -p "$BK_PAAS_MYSQL_PORT" -a $slave_ip -D >>/etc/consul.d/service/mysql-default.json;fi"
			./pcmd.sh -H $slave_ip "consul reload"
			# 解锁旧的master库
			#mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $master_ip -P $BK_PAAS_MYSQL_PORT -e "UNLOCK TABLES;"
			# 配置新的mysql主从
		        #for ip in "${SLAVE_HOST[@]}";do
                        	#./pcmd.sh -H $ip "mysql --login-path=default-root -e \"STOP SLAVE;\""
                        	#./pcmd.sh -H $ip "mysql --login-path=default-root -e \"RESET SLAVE ALL;\""
                        	#./pcmd.sh -H $ip "mysql --login-path=default-root -e \"CHANGE MASTER TO MASTER_HOST='$MASTER_HOST', MASTER_USER='$MASTER_USER', MASTER_PASSWORD='$MASTER_PASSWORD', MASTER_LOG_FILE='$MASTER_LOG_FILE', MASTER_LOG_POS=$MASTER_LOG_POS;\""
                        	#./pcmd.sh -H $ip "mysql --login-path=default-root -e \"START SLAVE;\""
				#replication_status=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{print $2}')
				#sql_running=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Slave_SQL_Running:" | awk '{print $2}')
				#if [ "$replication_status" == "Yes" && "$sql_running" == "Yes" ];then
				#	green_echo "$ip{slave} -->> $slave_ip{master} [SUCCESS] => 新的主从配置成功,状态为Yes."
				#else
				#	replicaiton_error=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Last_SQL_Error:" | awk '{print $2}')
				#	red_echo "$ip{slave} -->> $slave_ip{master} [FAIL] => 新的主从状态检查不通过,请手动检查报错."	
				#	red_echo "报错信息：$replicaiton_error"
				#fi
                	#done
			# 修改中控机install.config,并同步到其他机器
                        yellow_echo "修改install.config,备份到${SELF_DIR}_$(date +%Y%m%d%H%M)"
                        cp -ar  "${SELF_DIR}"  "${SELF_DIR}_$(date +%Y%m%d%H%M)"  
                	sed -i "/$master_ip/s/mysql(master)/mysql(slave)/g" install.config
                	sed -i "/$slave_ip/s/mysql(slave)/mysql(master)/g" install.config
                	./bkcli install bkenv
                	./bkcli sync common
			# 修改中控机的mysql --login配置
                        yellow_echo "重新配置中控机快捷登录,原.mylogin.cnf备份至/tmp/backup/mysql_login_$(date +%F)"
			mkdir -p /tmp/backup/mysql_login_$(date +%F)
			mv -f /root/.mylogin.cnf /tmp/backup/mysql_login_$(date +%F)
			for project in ${projects[@]}; do
				./bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,${project}"]}" -h "$slave_ip" -u "root" -p "$BK_MYSQL_ADMIN_PASSWORD"
			done
			./bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,default"]}" -h "$slave_ip" -u "root" -p "$BK_MYSQL_ADMIN_PASSWORD"
			#if lsof -i:$BK_PAAS_MYSQL_PORT -sTCP:LISTEN 1>/dev/null 2>&1;then
                        # 修复中控机刚好是mysql的情况，修复mysql服务停止了之后，授权异常的问题2024.05.17
                        if [[ $CONTROLLER_IP == $slave_ip || $CONTROLLER_IP == $master_ip ]];then
		        expect -c "
                        spawn mysql_config_editor set --skip-warn --login-path=default-root   --socket=/var/run/mysql/default.mysql.socket --user=$USERNAME --password
                        expect -nocase \"Enter password:\" {send \"$BK_MYSQL_ADMIN_PASSWORD\r\"; sleep 1; interact}"	
                        fi
                       consul reload
                       sleep 1
                       yellow_echo "检查是否dig出正常的主库IP"
                       dig mysql-default.service.consul
                #else
			#replicaiton_error=$(mysql -u$BK_MYSQL_ADMIN_USER -p"$BK_MYSQL_ADMIN_PASSWORD" -h $slave_ip -P $BK_PAAS_MYSQL_PORT -e "SHOW SLAVE STATUS\G" | grep "Last_SQL_Error:" | awk '{print $2}')
                        #red_echo "$slave_ip{slave} -->> $master_ip{master} [FAIL] => 主从状态未正常运行，请检查"
			#red_echo "报错信息：$replicaiton_error"
			#exit 1
		#fi
	else
                red_echo "[FAIL] => 请输入要切换的slave ip."
                exit 1
	fi
else
	red_echo "[FAIL] => master_ip不存在,请检查"
	exit 1
fi
