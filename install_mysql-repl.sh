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

SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/load_env.sh
source "${SELF_DIR}"/initdata.sh
source "${SELF_DIR}"/tools.sh
source "${SELF_DIR}"/utils.fc

set -e

source <(/opt/py36/bin/python ${SELF_DIR}/qq.py  -s -P ${SELF_DIR}/bin/default/port.yaml)
projects=${_projects["mysql"]}

mysql_master=$(cat install.config|grep "mysql(master)")
mysql_slave=$(cat install.config|grep "mysql(slave)")

mysql_master_count=$(cat install.config|grep "mysql(master)" | wc -l)
mysql_slave_count=$(cat install.config|grep "mysql(slave)" | wc -l)

mysql_master_ip=$(cat install.config|grep "mysql(master)" | awk '{print $1}')
mysql_slave_ip=$(cat install.config|grep "mysql(slave)" | awk '{print $1}')

data_dir="$(dirname $(pwd))"
dbbak_dir="${data_dir}/dbbak/mysql_$(date +%F)"

xtra_pkgs="percona-xtrabackup-24.x86_64"
if ! [ -z "${BK_MYSQL_SLAVE_IP_COMMA}" ];then
        if is_string_in_array "${BK_MYSQL_MASTER_IP_COMMA}" "${BK_MYSQL_SLAVE_IP[@]}";then
                err "mysql(master) mysql(slave) ���可部署在同一台服务器"
        fi
fi

if [ -n "$mysql_master" ];then
        if [ -n "$mysql_slave" ];then
                if [ "$mysql_master_count" -gt 1 ];then
                        red_echo "[FAIL] => mysql(master)数量大于1,mysql(master)只能存在一台"
                        exit 1
                else 
                        if [ "$mysql_slave_count" -gt 2 ];then
                                red_echo "[FAIL] => mysql(slave)数量大于1,mysql(slave)最多只能部署两台"
                                exit 1
                        else
                                for ip in ${mysql_slave_ip[@]};do
                                        yellow_echo "[INFO] => $ip:安装mysql_slave"
                                done
                                "${CTRL_DIR}"/pcmd.sh -m mysql_slave "${CTRL_DIR}/bin/install_mysql.sh -n 'default' -P ${_project_port["mysql,default"]} -p '$BK_MYSQL_ADMIN_PASSWORD' -d '${INSTALL_PATH}'/public/mysql -l '${INSTALL_PATH}'/logs/mysql -b \$LAN_IP -i"
                                for ip1 in ${mysql_slave_ip[@]};do
                                        yellow_echo "[INFO] => $ip1:配置mysql-login的default-root"
                                        ssh "$ip1" "$CTRL_DIR/bin/setup_mysql_loginpath.sh -n 'default-root' -h '/var/run/mysql/default.mysql.socket' -u 'root' -p '$BK_MYSQL_ADMIN_PASSWORD'"
                                done
                                # mysql机器安装xtrabackup
                                ./pcmd.sh -m mysql "yum -y install $xtra_pkgs"
                                # 调用initdata.sh脚本初始化mysql
                                _initdata_mysql
                                green_echo "# 为master,slave创建对应用户并授权"
                                ./pcmd.sh -H $mysql_master_ip "mysql --login-path=default-root -e \"CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$BK_MYSQL_ADMIN_PASSWORD';\""
                                ./pcmd.sh -H $mysql_master_ip "mysql --login-path=default-root -e \"GRANT REPLICATION SLAVE ON *.* TO 'root'@'%';\""
                                ./pcmd.sh -H $mysql_master_ip "mysql --login-path=default-root -e \"FLUSH PRIVILEGES;\""

                                for ip2 in ${mysql_slave_ip[@]};do
                                        ./pcmd.sh -H $ip2 "mysql --login-path=default-root -e \"CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$BK_MYSQL_ADMIN_PASSWORD';\""
                                        ./pcmd.sh -H $ip2 "mysql --login-path=default-root -e \"GRANT REPLICATION SLAVE ON *.* TO 'root'@'%';\""
                                        ./pcmd.sh -H $ip2 "mysql --login-path=default-root -e \"FLUSH PRIVILEGES;\""
                                done
                                green_echo "# 使用xtrabackup备份mysql(master)数据"
                                ./pcmd.sh -H $mysql_master_ip "mkdir -p $dbbak_dir"
                                ./pcmd.sh -H $mysql_master_ip "xtrabackup --defaults-file=/etc/mysql/default.my.cnf --login-path=default-root --backup --target-dir=${dbbak_dir}"
                                ./pcmd.sh -H $mysql_master_ip "xtrabackup --defaults-file=/etc/mysql/default.my.cnf --login-path=default-root --prepare --target-dir=${dbbak_dir}"
                                ./pcmd.sh -H $mysql_master_ip "cd ${data_dir}/dbbak/; tar -czf mysql_$(date +%F).tar.gz mysql_$(date +%F)"
                                green_echo "# 传输备份数据到slave并恢复"
                                for ip3 in ${mysql_slave_ip[@]};do
                                        ./pcmd.sh -H $ip3 "systemctl stop mysql@default"
                                        ./pcmd.sh -H $ip3 "mkdir -p ${data_dir}/dbbak/"
                                        ./pcmd.sh -H $mysql_master_ip "scp -o 'StrictHostKeyChecking no' ${dbbak_dir}.tar.gz $ip3:${data_dir}/dbbak/"
                                        ./pcmd.sh -H $ip3 "cd ${data_dir}/dbbak/; tar -zxf mysql_$(date +%F).tar.gz"
                                        # 备份slave原数据
                                        ./pcmd.sh -H $ip3 "mv ${INSTALL_PATH}/public/mysql/default/data{,_bak_$(date +%F_%T)}"
                                        # 还原master数据到slave,并拉起服务
                                        ./pcmd.sh -H $ip3 "xtrabackup --defaults-file=/etc/mysql/default.my.cnf --login-path=default-root --move-back --target-dir=${dbbak_dir}"
                                        ./pcmd.sh -H $ip3 "chown -R mysql:mysql ${INSTALL_PATH}/public/mysql/default/data"
                                        ./pcmd.sh -H $ip3 "systemctl start mysql@default"
                                done

                                sleep 10
                                bash ./configure_mysql_master-slave.sh
                                sleep 10
                                bash ./check_master-slave.sh
                        fi
                fi
        else
                red_echo "[FAIL] => install.config不存在mysql(slave),添加对应的角色再安装"
                exit 1
        fi
else
        red_echo "[FAIL] => install.config不存在mysql(master),添加对应的角色再安装"
        exit 1
fi