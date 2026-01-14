#!/bin/bash
# vim:ft=sh sts=4 ts=4 expandtab
#saas*=app_code:key1=value1;key2=value2
set -o pipefail 
if [ ! -f install_saas.env ];then 
    echo "install_saas.env dose not exit, please input first"
    exit 1
fi
source /data/install/load_env.sh
source install_saas.env
source /data/install/utils.fc

data_install_path="/data/install"

install_saas()
{
    app_code=$1
    saas_var=$2
    src_pkg=$3
    echo "Delete previous values before inserting data repeatedly"
    delete_sql="DELETE FROM paas_app_envvars WHERE app_code='$app_code'"
    ssh $BK_MYSQL_IP "docker exec mysql-client mysql --login-path=default-root open_paas -e     \"${delete_sql}\""
    if [[ $saas_var != 1 ]];then
        for str_var in `eval echo  '$'saas_var|sed 's/;/ /g'`
        do
              echo $str_var
            k=$(echo $str_var |awk -F '=' '{print $2}')
                     v=$(echo $str_var |awk -F '=' '{print $3}')
            if [[ -z $k || -z $v ]];then
                echo "$app_code have empty key or value"
                exit 1    
            else
                insert_sql="INSERT INTO paas_app_envvars (app_code, mode, name, value, intro) VALUES('$app_code', 'all', '$k', '$v', 'Set by self script') ON DUPLICATE KEY UPDATE value='$v', intro='Update by self script'"
                echo $insert_sql
                ssh $BK_MYSQL_IP "docker exec mysql-client mysql --login-path=default-root open_paas -e \"${insert_sql}\""
            fi

        done
    fi
#install
    ctl_path=$(pwd)
#    ./bkcli install saas-o $app_code && echo $app_code >> $ctl_path/.step_canway_saas 
    echo "/opt/py36/bin/python ${data_install_path}/bin/saas.py -e appo -n $app_code -k ${src_pkg} -f ${data_install_path}/bin/04-final/paas.env"
    /opt/py36/bin/python ${data_install_path}/bin/saas.py -e appo -n $app_code -k ${src_pkg} -f ${data_install_path}/bin/04-final/paas.env && echo $app_code >> $ctl_path/.step_canway_saas
#add whitelist
    add_skip_auth_appcode $app_code  $BK_MYSQL_IP $BK_MYSQL_ADMIN_USER $BK_MYSQL_ADMIN_PASSWORD
}  

add_skip_auth_appcode()
{
APP_CODE=$1
HOST_IP=$2
USER=$3
export MYSQL_PWD=$4
# check 
if ! docker exec mysql-client mysql -u$USER  -h$HOST_IP -p$MYSQL_PWD -D open_paas -e 'show tables' >/dev/null; then
    echo "open_paas database not exists."
    exit 1
fi  

# 蓝鲸自己后台默认的app_code需要添加到esb的免登录态白名单中
wlist=$(docker exec mysql-client mysql -u$USER  -h$HOST_IP -p$MYSQL_PWD -D open_paas -sNe "select wlist from esb_function_controller where func_code = 'user_auth::skip_user_auth'")

if ! echo "$wlist" | grep -qw "$APP_CODE"; then
    if docker exec mysql-client mysql -u$USER  -h$HOST_IP -p$MYSQL_PWD -D open_paas -e "update esb_function_controller set wlist=concat(wlist, ',$APP_CODE') where func_code = 'user_auth::skip_user_auth'"; then
        echo "add $APP_CODE to esb skip_user_auth white list succeed"
    else
        echo "add $APP_CODE to esb skip_user_auth white list failed"
        exit 1
    fi  
fi  
}



#main process
if [ ! -f .step_canway_saas ];then
    touch .step_canway_saas
fi
if [ ! -f canway_saas_vars.txt ];then
    echo "canway_saas_vars.txt dons't exist"
        echo "Please input canway_saas_vars.txt first"
    exit 
fi

if [[ $# -gt 0 ]];then
    for app_code in $@
    do
        if [[ `cat canway_saas_vars.txt |grep -v "^#" |grep "${app_code}:"|wc -l` -eq 0 ]];then
            echo -e "\n\e[1;33m$app_code not in canway_saas_vars.txt\e[0m"
            saas_var='1'
            echo -e "\n\e[1;33mAre you sure continue? (y/n [n]): \e[0m"
            read singal
                if [ $singal != "y" ]; then
                    exit 0
            else
                    echo "continue install $app_code"
               fi
        else
            saas_var_tmp=$(grep "${app_code}:" canway_saas_vars.txt |grep -v "^#" |sed 's/ //g'|sed 's/:/=/'|sed 's/;/&stand=/g'|sed 's/;/#/g')
            saas_var=$(eval echo ${saas_var_tmp} |sed "s/stand/$app_code/g" |sed 's/ /;/g' |sed 's/#/;/g')
        fi
        if [[ $(grep $app_code .step_canway_saas |wc -l) -eq 0 ]];then
            dir_src="${BK_PKG_SRC_PATH}"/official_saas
            v_num1=$(ls $dir_src |grep ".*$app_code.*.tar.gz$" |wc -l)
            if [[ $v_num1 -eq 1 ]];then
                src_pkgname=$(ls -rt $dir_src |grep $app_code |tail -1)
                src_pkgpath=$dir_src/$src_pkgname
                           install_saas $app_code $saas_var $src_pkgpath
            elif [[ $v_num1 -eq 0 ]];then
                echo "Can not find $app_code package from $dir_src"
                exit 1
            else 
                echo "There have more package about $app_code in $dir_src. unsure upload which one"
                exit 1
            fi
        else
            echo "skip: $app_code already installed"
        fi
    done
fi

