#!/usr/bin/env bash
# vim:ft=sh sts=4 ts=4 sw=4 expandtab nu ai
# set -euo pipefail
SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/load_env.sh
source "${SELF_DIR}"/initdata.sh
source "${SELF_DIR}"/tools.sh

## 获取平台版本: 主版本.次版本
PLAT_VER=$(cat "$BK_PKG_SRC_PATH"/VERSION | grep -oP '(\d+.\d+)' | tr -d "\n")

set -e

install_backup () {
    ${SELF_DIR}/pcmd.sh -H $BK_MYSQL_IP0 "source ${SELF_DIR}/tools.sh;addcron_for_dbbackup_mysql"
    ${SELF_DIR}/pcmd.sh -H $BK_MONGODB_IP0 "source ${SELF_DIR}/tools.sh;addcron_for_dbbackup_mongodb"
    emphasize "为 蓝鲸部署备份定时一键备份,每天凌晨3点备份MYSQL，4点备份mongodb 备份路径为/data/bkbackup"
    bash "${SELF_DIR}"/canway/backupTools/start_backup.sh
    emphasize "为各蓝鲸机器配置清理日志策略"
    ${SELF_DIR}/pcmd.sh -m all "bash ${SELF_DIR}/delete_log.sh"
    #${SELF_DIR}/pcmd.sh -m all "echo '0 2 * * *  /usr/bin/find $INSTALL_PATH/logs/ -type f \( -name "*.log.*" -o -name "*.log" \) -mtime +15 -size +1c -delete' | crontab -;crontab -l"
}

install_cwlicense () {
# 安装嘉为证书服务
    local module=cwlicense
    local port=${BK_CWLICENSE_PORT}
    entcode=
    if [[ -f ${BK_PKG_SRC_PATH}/ENTERPRISE ]];
    then
        entcode=$(cat ${BK_PKG_SRC_PATH}/ENTERPRISE)
    else
        red_echo "${BK_PKG_SRC_PATH}/ENTERPRISE 不存在，请检查"
        exit 1
    fi

    # 挂载nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "为 cwlicense 挂载 NFS 路径: $BK_NFS_IP0"
        pcmdrc ${module} "_mount_shared_nfs cwlicense"
    fi

    emphasize "安装嘉为 cwlicense 许可服务: ${BK_CWLICENSE_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -m ${module}  ${CTRL_DIR}/bin/install_cwlicense.sh -b \$LAN_IP -c ${entcode} -e "${CTRL_DIR}"/bin/04-final/cwlicense.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}

    # 注册consul
    emphasize "注册 cw-license 的 consul 服务: ${BK_CWLICENSE_IP_COMMA}:${BK_CWLICENSE_PORT} "
    reg_consul_svc "cw-license" "${port}" "${BK_CWLICENSE_IP_COMMA}"



    emphasize "添加主机模块标记"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_iptables () {
  ${SELF_DIR}/pcmd.sh -m all "bash ${SELF_DIR}/iptables.sh --start"
  emphasize "为各蓝鲸机器配置清理防火墙策略，请注意，如后续进行扩容或迁移，请重新执行此命令。"
}

install_nfs () {
    emphasize "install nfs on host: ${BK_NFS_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m nfs "${CTRL_DIR}/bin/install_nfs.sh -d ${INSTALL_PATH}/public/nfs"
    emphasize "sign host as module"
    pcmdrc "${BK_NFS_IP_COMMA}" "_sign_host_as_module nfs"
}

install_yum () {

    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local HTTP_PORT=${_project_port["yum,default"]}
    local PYTHON_PATH="/opt/py27/bin/python"
    [[ -d "${BK_YUM_PKG_PATH}"/repodata ]]  && rm -rf "'${BK_YUM_PKG_PATH}'/repodata"
    if [[ $PLAT_VER < 4.0 ]]; then
        emphasize "install bk yum on host: 中控机"
        "${SELF_DIR}"/bin/install_yum.sh -P "${HTTP_PORT}" -p /opt/yum -python "${PYTHON_PATH}"
        emphasize "add or update repo on host: ${ALL_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -m ALL "'${SELF_DIR}'/bin/setup_local_yum.sh -l http://$LAN_IP:${HTTP_PORT} -a"
        emphasize "sign host as module"
        pcmdrc "${LAN_IP}" "_sign_host_as_module yum"
    fi

    "${SELF_DIR}"/pcmd.sh -m ALL "yum makecache"
    # special: 蓝鲸业务中控机模块标记
    pcmdrc "${LAN_IP}" "_sign_host_as_module controller_ip"
}

install_beanstalk () {
    local module="beanstalk"
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    emphasize  "install beanstalk on host: ${BK_BEANSTALK_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -m beanstalk "yum install  -y beanstalkd && systemctl enable --now beanstalkd && systemctl start beanstalkd"
    # 注册consul
    emphasize "register ${_project_port["$module,default"]}  consul server  on host: ${BK_BEANSTALK_IP_COMMA}"
    reg_consul_svc "${_project_consul["$module,default"]}" "${_project_port["$module,default"]}" "${BK_BEANSTALK_IP_COMMA}"
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_consul () {
    local module=consul 
    SERVER_IP="${BK_CONSUL_IP[@]}"
    # 允许返回码非0，兼容所有的服务器都是consul server
    set +e
    BK_CONSUL_CLIENT_IP=($(printf "%s\n" ${ALL_IP[@]}  | grep -vwE ""${SERVER_IP// /|}"" ))
    set -e
    # 部署consul server
    emphasize "install consul server on host: ${BK_CONSUL_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m $module  "${CTRL_DIR}/bin/install_consul.sh  \
                -e '$BK_CONSUL_KEYSTR_32BYTES' -j '$BK_CONSUL_IP_COMMA' -r server --dns-port 53 -b \$LAN_IP -n '${#BK_CONSUL_IP[@]}'"
    # 部署consul client
    if ! [[ -z "$BK_CONSUL_CLIENT_IP" ]]; then
        emphasize "install consul client on host: ${BK_CONSUL_CLIENT_IP[@]}"
        "${SELF_DIR}"/pcmd.sh -H $(printf "%s," "${BK_CONSUL_CLIENT_IP[@]}") "${CTRL_DIR}/bin/install_consul.sh \
                    -e '$BK_CONSUL_KEYSTR_32BYTES' -j '$BK_CONSUL_IP_COMMA' -r client --dns-port 53 -b \$LAN_IP"
    fi
    emphasize "sign host as module"
    pcmdrc consul "_sign_host_as_module ${module}"
}

install_vault () {
    ## 由于插件路径绑定问题, vault 和 cwsm 模块角色一致.
    local module=cwsm 
    local VAULT_ENV=/etc/vault.d/vault.env

    # SERVER_IP="${BK_CWSM_IP[@]}"
    BK_VAULT_LEADER=${BK_CWSM_IP[0]}
    ## 这里先判断是否已经存在集群主节点，否则默认取第一个ip为主节点。
    for ip in ${BK_CWSM_IP[@]}; do
        source <("${SELF_DIR}"/pcmd.sh -H $ip "cat $VAULT_ENV" | grep "=")
        [[ -z $VAULT_TOKEN ]] && continue
        master_ip=$(curl -s --connect-timeout 2 --header "X-Vault-Token: $VAULT_TOKEN" \
            $VAULT_ADDR/v1/sys/ha-status | \
            jq '.data.nodes[] | select(.active_node == true).api_address' | grep -oP '(?<=http://)([\d.]+)')
        [[ -n $master_ip ]] && { BK_VAULT_LEADER=$master_ip; break; }
    done
    
    set +e
    BK_VAULT_FOLLOWER_IP=($(printf "%s\n" ${BK_CWSM_IP[@]}  | grep -vwE ""${BK_VAULT_LEADER// /|}"" ))
    set -e
    # 部署 vault leader server
    emphasize "install vault server on host: ${BK_CWSM_IP_COMMA}"
    # 这里拿第一个ip作为 leader 角色, 其它均为 follower 角色。
    ## 仅在 leader 角色执行 初始化 和 生成解封密钥。
    ## 其它 follower 角色 不用执行上述动作，直接加入集群即可。 
    emphasize "install vault leader on host: ${BK_VAULT_LEADER}"
    "${SELF_DIR}"/pcmd.sh -H $BK_VAULT_LEADER  "${CTRL_DIR}/bin/install_vault.sh  \
                -s '$BK_CWSM_IP_COMMA' -r leader -b \$LAN_IP"
    # 从leader角色获取解封密钥和token
    set +e
    source <("${SELF_DIR}"/pcmd.sh -H $BK_VAULT_LEADER "cat $VAULT_ENV" | grep "=")
    set -e
    if ! [[ -z "$BK_VAULT_FOLLOWER_IP" ]]; then
        emphasize "install vault follower on host: ${BK_VAULT_FOLLOWER_IP[@]}"
        "${SELF_DIR}"/pcmd.sh -H $(printf "%s," "${BK_VAULT_FOLLOWER_IP[@]}") "${CTRL_DIR}/bin/install_vault.sh \
                -e '$VAULT_TOKEN' -u '$VAULT_UNSEAL_KEY' -s '$BK_CWSM_IP_COMMA' -r follower -b \$LAN_IP"
    fi
    # emphasize "sign host as module"
    # pcmdrc consul "_sign_host_as_module ${module}"
}


install_cwsm () {
    # 安装嘉为凭据服务
    local module=cwsm
    local port=${BK_CWSM_PORT}

    emphasize "migrate ${module} sql"
    migrate_sql $module
    [[ $? -ne 0 ]] &&  err "导入sql失败,请检查" 

    emphasize "安装嘉为凭据(cwsm)服务: ${BK_CWSM_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -m ${module}  ${CTRL_DIR}/bin/install_cwsm.sh -b \$LAN_IP -e "${CTRL_DIR}"/bin/04-final/cwsm.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}
    # 注册 cwsm consul
    emphasize "注册 cwsm 的 consul 服务: ${BK_CWSM_IP_COMMA}:${BK_CWSM_PORT} "
    reg_consul_svc "cwsm" "${port}" "${BK_CWSM_IP_COMMA}"

    emphasize "添加saas白名单"
    "${SELF_DIR}"/bin/add_skip_auth_appcode.sh ${module} mysql-paas

    emphasize "添加主机模块标记"
    pcmdrc ${module} "_sign_host_as_module ${module}"

}

install_doris() {
    ## 安装doris 
    local module=doris

    # 同步java8安装包
    emphasize "sync java8.tgz  to $module host: ${BK_DORIS_IP_COMMA}"
    "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/java8.tgz" "${BK_PKG_SRC_PATH}/"

    # Doris服务器安装JAVA依赖
    emphasize "install java on host: ${BK_DORIS_FE_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_DORIS_FE_IP_COMMA}" "${CTRL_DIR}/bin/install_java.sh -p '${INSTALL_PATH}' -f '${BK_PKG_SRC_PATH}'/java8.tgz"

    # 部署 doris FE
    emphasize "安装apache doris fe服务: ${BK_DORIS_FE_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -H "${BK_DORIS_FE_IP_COMMA}"  ${CTRL_DIR}/bin/install_doris.sh -b \$LAN_IP \
        -e "${CTRL_DIR}"/bin/04-final/doris.env -s ${BK_DORIS_FE_IP_COMMA} -p ${INSTALL_PATH} -r fe 
    # 部署 doris BE
    emphasize "安装apache doris be服务: ${BK_DORIS_BE_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -H "${BK_DORIS_BE_IP_COMMA}" ${CTRL_DIR}/bin/install_doris.sh -b \$LAN_IP \
        -e "${CTRL_DIR}"/bin/04-final/doris.env -s ${BK_DORIS_BE_IP_COMMA} -p ${INSTALL_PATH} -r be
    # 初始化doris
    _initdata_doris
    # 如存在多个fe, 则添加为 FOLLOWER 角色
    # 备注： 官方提供fe/be 增删 http api 还处于dev状态 2023/10/19
    # 链接地址：https://doris.apache.org/docs/1.2/admin-manual/http-actions/fe/node-action/
    #
    # 获取当前各个角色ip
    set +e
    result=$(curl -s -u "root:$BK_DORIS_ADMIN_PASSWORD" http://${BK_DORIS_FE_IP}:$BK_DORIS_FE_HTTP_PORT/rest/v2/manager/node/node_list 2>/dev/null)
    if [[ $(echo $result | jq .code) -ne 0 ]]; then
        err "从ip:[$BK_DORIS_FE_IP]获取 doris 节点信息失败，请检查"
    fi
    fe_master_list=( $(curl -s -u "root:$BK_DORIS_ADMIN_PASSWORD" \
        http://${BK_DORIS_FE_IP}:$BK_DORIS_FE_HTTP_PORT/rest/v2/manager/node/frontends | \
        jq -r '.data.rows[] | select(.[8] == "true") | .[1]') )
    doris_exist_fe=$(echo $result | jq -r '.data.frontend | join(" ")')
    doris_exist_be=$(echo $result | jq -r '.data.backend | join(" ")')
    set -e
    ## 这里先判断是否已经存在FE集群主节点。
    [[ -z $fe_master_list ]] && err "Doris FE主节点不存在, 请检查。"
    # 将其它 doris FE 以follower身份加入 FE master
    read -r fe_ip <<< "${BK_DORIS_FE_IP_COMMA//,/ }"
    for ip in $fe_ip; do
        if ! egrep "\<$ip\>" <<<$doris_exist_fe; then
            "${SELF_DIR}"/pcmd.sh -H "$ip" "${CTRL_DIR}/bin/setup_doris_fe_rs.sh -m ${fe_master_list[0]} -p ${INSTALL_PATH} -a add"
            echo "use information_schema; ALTER SYSTEM ADD FOLLOWER '$ip:$BK_DORIS_FE_EDIT_PORT';" | \
                mysql -h"$BK_DORIS_FE_IP" -u"$BK_DORIS_ADMIN_USER" -P $BK_DORIS_FE_QUERY_PORT -p"$BK_DORIS_ADMIN_PASSWORD"
            emphasize "成功添加doris FE follower host: $ip 到FE host:$BK_DORIS_FE_IP."
        fi
    done 
    # 将 doris BE 信息加入到 FE
    read -r be_ip <<< "${BK_DORIS_BE_IP_COMMA//,/ }"
    for ip in $be_ip; do
        if ! egrep "\<$ip\>" <<<$doris_exist_be; then
            echo "use information_schema; ALTER SYSTEM ADD BACKEND '$ip:$BK_DORIS_BE_HEARTBEAT_PORT';" | \
                mysql -h"$BK_DORIS_FE_IP" -u"$BK_DORIS_ADMIN_USER" -P $BK_DORIS_FE_QUERY_PORT -p"$BK_DORIS_ADMIN_PASSWORD"
            emphasize "成功添加doris BE host: $ip 到FE host:$BK_DORIS_FE_IP."
        fi
    done 
    # 注册 cwreport consul
    emphasize "注册 doris fe 的 consul 服务: ${BK_DORIS_FE_IP_COMMA}:$BK_DORIS_FE_HTTP_PORT "
    reg_consul_svc "doris-fe" "$BK_DORIS_FE_HTTP_PORT" "${BK_DORIS_FE_IP_COMMA}"
    emphasize "注册 doris be 的 consul 服务: ${BK_DORIS_FE_IP_COMMA}:$BK_DORIS_BE_HEARTBEAT_PORT "
    reg_consul_svc "doris-be" "$BK_DORIS_BE_HEARTBEAT_PORT" "${BK_DORIS_BE_IP_COMMA}"
    emphasize "添加主机模块标记"
    pcmdrc ${module} "_sign_host_as_module ${module}"

}


install_cwreport() {
    ## 安装嘉为报表服务
    local module=cwreport

    # 同步java8安装包
    emphasize "sync java8.tgz  to $module host: ${BK_CWREPORT_IP_COMMA}"
    "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/java8.tgz" "${BK_PKG_SRC_PATH}/"
    # 报表服务安装JAVA依赖
    emphasize "install java on host: ${BK_CWREPORT_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_java.sh -p '${INSTALL_PATH}' -f '${BK_PKG_SRC_PATH}'/java8.tgz"
    # 配置前端saas nginx配置
    install_consul_template $module "${BK_CWREPORT_IP_COMMA}"
    emphasize "安装嘉为报表服务: ${BK_CWREPORT_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -m "${module}" ${CTRL_DIR}/bin/install_cwreport.sh -b \$LAN_IP \
        -e "${CTRL_DIR}"/bin/04-final/cwreport.env -s "${BK_PKG_SRC_PATH}" -p ${INSTALL_PATH}
    # 初始化 db数据
    _initdata_cwreport
    emphasize "grant rabbitmq private for ${module}"
    grant_rabbitmq_pri $module
    # 权限模型
    emphasize "Registration authority model for ${module}"
    bkiam_migrate ${module}
    result=$(curl -s http://$BK_CWREPORT_IP:$BK_CWREPORT_SAAS_PORT/report/insight/api/service/insight/permission/init)
    if  [[ $(echo $result | jq .code) -ne 0 ]]; then
       warn "报表服务权限初始化失败,请稍后尝试" 
    fi
    # 注册 cwreport consul
    emphasize "注册 cwreport 的 consul 服务: ${BK_CWREPORT_IP_COMMA}:${BK_CWREPORT_SAAS_PORT} "
    reg_consul_svc "$module" "${BK_CWREPORT_SAAS_PORT}" "${BK_CWREPORT_IP_COMMA}"
    emphasize "添加saas白名单"
    "${SELF_DIR}"/bin/add_skip_auth_appcode.sh $BK_CWREPORT_APP_CODE mysql-paas
    emphasize "添加主机模块标记"
    pcmdrc ${module} "_sign_host_as_module ${module}"

}

install_pypi () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=pypi
    local http_port=${_project_port["$module,default"]}
    local pkg_path="${BK_PYPI_PKG_PATH}"
    local python_path=/opt/py27
    if [ ! -d $pkg_path ];then err "$pkg_path不存在";fi

    # 中控机部署pypiserver
    "${SELF_DIR}"/bin/setup_local_pypiserver.sh -P $python_path -d "${pkg_path}" -a -p "${http_port}" -s "${BK_PKG_SRC_PATH}" -l "${LAN_IP}"  || return 1

    # 所有蓝鲸服务器配置PYPI源
    "${SELF_DIR}"/pcmd.sh -H "$ALL_IP_COMMA" "${CTRL_DIR}"/bin/setup_local_pypiserver.sh -c

    # 注册consul
    reg_consul_svc "${_project_consul["$module,default"]}" "${http_port}" "$LAN_IP"
}

_install_yq () {

    local module=$1

    if [[ "$module" == "controller" ]]; then
         rsync -a "${CTRL_DIR}"/bin/yq /usr/local/bin/ && chmod +x /usr/local/bin/yq
    else
        "${SELF_DIR}"/pcmd.sh -m "$module" "rsync -a ${CTRL_DIR}/bin/yq /usr/local/bin/ && chmod +x /usr/local/bin/yq"
    fi
}
install_controller () {
    emphasize "install controller source"
    local extar="$1"
    if [ -z "${extar}" ]; then
        "${CTRL_DIR}"/bin/install_controller.sh
        _install_yq controller
    else
        "${CTRL_DIR}"/bin/install_controller.sh -e
        _install_yq controller
    fi
}

install_bkenv () {
    # 不完善 存在模块排序与互相依赖问题
    local module m
    # local host_tag_file=dbadmin.env
    local projects=(dbadmin.env 
                    global.env 
                    paas.env  
                    license.env 
                    bkiam.env  
                    bkssm.env 
                    bkapigw.env
                    bkauth.env
                    usermgr.env 
                    paasagent.env 
                    cmdb.env 
                    gse.env 
                    job.env 
                    paas_plugins.env 
                    bknodeman.env 
                    bkmonitorv3.env  
                    bklog.env 
                    lesscode.env
                    fta.env
                    cwlicense.env
                    cwsm.env
                    doris.env
                    cwreport.env
                    bkiam_search_engine.env)

    # 生成bkrc
    set +e
    gen_bkrc
    
    cd "${SELF_DIR}"/bin/default
    for m in "${projects[@]}"; do
        module=${m%.env}
        # generate文件只生成一次
        if [[ ! -f ${HOME}/.tag/$m ]]; then
            case $module in
                global|license|paasagent) : ;;
                *) "${SELF_DIR}"/bin/generate_blueking_generate_envvars.sh "$module" > "${SELF_DIR}/bin/01-generate/$module.env" && make_tag "$m" ;;
            esac
        fi
        if [[ $module != dbadmin ]]; then
            "${SELF_DIR}"/bin/merge_env.sh "$module"
        fi
    done
    # 修正因早期部署无法正常更新job证书密码的问题
    if [[ -d $BK_CERT_PATH ]];then
        gse_pass=$(awk '$1 == "gse_job_api_client.p12" {print $NF}' "$BK_CERT_PATH"/passwd.txt)
        job_pass=$(awk '$1 == "job_server.p12" {print $NF}' "$BK_CERT_PATH"/passwd.txt)
    else
        source ~/.bkrc
        gse_pass=$(awk '$1 == "gse_job_api_client.p12" {print $NF}' "$BK_PKG_SRC_PATH"/cert/passwd.txt)
        job_pass=$(awk '$1 == "job_server.p12" {print $NF}' "$BK_PKG_SRC_PATH"/cert/passwd.txt)
    fi
    if [[ -z $gse_pass || -z $job_pass ]];then
    sed -i.bak "s/BK_GSE_SSL_KEYSTORE_PASSWORD=.*/BK_GSE_SSL_KEYSTORE_PASSWORD=$gse_pass/g" "$SELF_DIR"/bin/01-generate/job.env
    sed -i "s/BK_GSE_SSL_TRUSTSTORE_PASSWORD=.*/BK_GSE_SSL_TRUSTSTORE_PASSWORD=$gse_pass/g" "$SELF_DIR"/bin/01-generate/job.env
    sed -i "s/BK_JOB_GATEWAY_SERVER_SSL_KEYSTORE_PASSWORD=.*/BK_JOB_GATEWAY_SERVER_SSL_KEYSTORE_PASSWORD=$job_pass/g" "$SELF_DIR"/bin/01-generate/job.env
    sed -i "s/BK_JOB_GATEWAY_SERVER_SSL_TRUSTSTORE_PASSWORD=.*/BK_JOB_GATEWAY_SERVER_SSL_TRUSTSTORE_PASSWORD=$job_pass/g" "$SELF_DIR"/bin/01-generate/job.env
    "${SELF_DIR}"/bin/merge_env.sh "job"
    fi

    set -e
}


install_kafka () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=kafka
    local kafka_port=${_project_port["kafka,default"]}
    local zk_port=${_project_port["zk,default"]}
    local consul=${_project_consul["kafka,default"]}
    # 同步java8安装包
    emphasize "sync java8.tgz  to kafka host: ${BK_KAFKA_IP_COMMA}"
    "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/java8.tgz" "${BK_PKG_SRC_PATH}/"

    # KAFKA服务器安装JAVA依赖
    emphasize "install java on host: ${BK_KAFKA_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_java.sh -p '${INSTALL_PATH}' -f '${BK_PKG_SRC_PATH}'/java8.tgz"

    # 部署 kafka
    emphasize "install kafka on host: ${BK_KAFKA_IP_COMMA}"
    ZK_HOSTS_TMP=$(printf "%s:${zk_port}," "${BK_ZK_IP[@]}")
    ZK_HOSTS=${ZK_HOSTS_TMP%,}  # 去除字符串尾部逗号
    "${SELF_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_kafka.sh -j $BK_KAFKA_IP_COMMA -z '${ZK_HOSTS}'/common_kafka -b \$LAN_IP -d ${INSTALL_PATH}/public/kafka -p '${kafka_port}'"

    # 注册 kafka consul
    emphasize "register  ${consul} consul server  on host: ${BK_KAFKA_IP_COMMA} "
    reg_consul_svc "${consul}" "${kafka_port}" "${BK_KAFKA_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_tdsql () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py  -s -P ${SELF_DIR}/bin/default/port.yaml)
    projects=${_projects["mysql"]}
    # 安装 tdsql
    local mysql_ip=$BK_MYSQL_TDSQL_IP
    #local BK_TDSQL_PATH=/data1/tdengine/data/4002/prod/mysql.sock
    #port=${_project_port["mysql,default"]}
    if ! grep "${mysql_ip}" "${SELF_DIR}"/bin/02-dynamic/hosts.env | grep "BK_MYSQL_TDSQL_.*_IP_COMMA" >/dev/null; then
        # tdsql不安装，注释安装逻辑
        #"${CTRL_DIR}"/pcmd.sh -H "${mysql_ip}" "${CTRL_DIR}/bin/install_mysql.sh -n 'default' -P ${_project_port["mysql,default"]} -p '$BK_MYSQL_ADMIN_PASSWORD' -d '${INSTALL_PATH}'/public/mysql -l '${INSTALL_PATH}'/logs/mysql -b \$LAN_IP -i"
        # # mysql机器配置login-path
        emphasize "set mysql login path 'default-root' on host: ${mysql_ip}"
        # TODO: 使用pcmd时会出现意想不到的bug，可能和tty allocation有关，待定位，临时用原生ssh代替
        #ssh "${mysql_ip}" "$CTRL_DIR/bin/setup_mysql_loginpath.sh -n 'default-root' -h '/var/run/mysql/default.mysql.socket' -u 'root' -p '$BK_MYSQL_ADMIN_PASSWORD'"
        # mysql机器配置default-root快捷登录,tdsql不建议直连socket,需改为proxy 连接到15002，20240419
        ssh "${mysql_ip}" "$CTRL_DIR/bin/setup_mysql_loginpath.sh -n 'default-root' -h "${mysql_ip}" -u '$BK_MYSQL_ADMIN_USER' -p '$BK_MYSQL_ADMIN_PASSWORD'" -P $port
        for project in ${projects[@]}; do
           target_ip=BK_MYSQL_${project^^}_IP_COMMA
           port=${_project_port["mysql,default"]}
           if [[ -z ${!target_ip} ]]; then
               # 中控机配置login-path
               emphasize "set mysql login path ${_project_consul["mysql,${project}"]} on host: 中控机"
               "${SELF_DIR}"/bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,${project}"]}" -h "${mysql_ip}" -u "tdsqlpcloud" -p "$BK_MYSQL_ADMIN_PASSWORD" -P $port
               # 配置mysql-模块consul解析
               emphasize "register ${_project_consul["mysql,${project}"]} on host ${mysql_ip}"
               reg_consul_svc "${_project_consul["mysql,${project}"]}" "${_project_port["mysql,${project}"]}" "${mysql_ip}"
          fi
        done
        emphasize "register mysql consul on host: ${mysql_ip}"
        # 配置mysql-default consul解析
        reg_consul_svc "${_project_consul["mysql,default"]}" "${_project_port["mysql,default"]}" "${mysql_ip}"

        # 中控机配置 default login-path
        emphasize "set mysql ${_project_consul["mysql,default"]} login path on host: 中控机"
        "${SELF_DIR}"/bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,default"]}" -h "${mysql_ip}" -u "$BK_MYSQL_ADMIN_USER" -p "$BK_MYSQL_ADMIN_PASSWORD" -P $port
    fi
    emphasize "sign host as module"
    pcmdrc mysql "_sign_host_as_module mysql"
}

install_tdsql_common () {
    _install_tdsql "$@"
    _initdata_mysql
}

install_mysql_common () {
    _install_mysql "$@"
    _initdata_mysql
    # 由于需要配置只读，配置主从顺序换到initdata mysql授权之后，防止无法写入
    mysql_slave_ip=$(cat install.config | grep mysql | grep slave |grep -v '#' | awk '{print $1}')
    if [ -n "$mysql_slave_ip" ]; then
    bash "${CTRL_DIR}"/configure_mysql_master-slave.sh
    fi
}

_install_mysql () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py  -s -P ${SELF_DIR}/bin/default/port.yaml)
    projects=${_projects["mysql"]}
    # 安装 mysql
    count_master=$(cat install.config | grep 'mysql(master)' |wc -l)
    if ! [ -z "${BK_MYSQL_SLAVE_IP_COMMA}" ];then
            if is_string_in_array "${BK_MYSQL_MASTER_IP_COMMA}" "${BK_MYSQL_SLAVE_IP[@]}";then
                    err "mysql(master) mysql(slave) 不可部署在同一台服务器"
            fi
    fi
    if [ $count_master -gt 1 ]; then
            echo "mysql(master)只能部署一个。"
            exit 1
    else
            master_ip=`cat install.config | grep 'mysql(master)' | awk '{print $1}'`
            if [ -n "$master_ip" ];then
                    mysql_ip=$BK_MYSQL_MASTER_IP0
            else
                    mysql_ip=$BK_MYSQL_IP0
            fi
            emphasize "install mysql on host: ${mysql_ip}"
            "${CTRL_DIR}"/pcmd.sh -H "${mysql_ip}" "${CTRL_DIR}/bin/install_mysql.sh -n 'default' -P ${_project_port["mysql,default"]} -p '$BK_MYSQL_ADMIN_PASSWORD' -d '${INSTALL_PATH}'/public/mysql -l '${INSTALL_PATH}'/logs/mysql -b \$LAN_IP -i"
            ## mysql机器配置login-path
            emphasize "set mysql login path 'default-root' on host: ${mysql_ip}"
            # TODO: 使用pcmd时会出现意想不到的bug，可能和tty allocation有关，待定位，临时用原生ssh代替
            ssh "${mysql_ip}" "$CTRL_DIR/bin/setup_mysql_loginpath.sh -n 'default-root' -h '/var/run/mysql/default.mysql.socket' -u 'root' -p '$BK_MYSQL_ADMIN_PASSWORD'"
            for project in ${projects[@]}; do
               target_ip=BK_MYSQL_${project^^}_IP_COMMA
               if [[ -z ${!target_ip} ]]; then 
                   # 中控机配置login-path
                   emphasize "set mysql login path ${_project_consul["mysql,${project}"]} on host: 中控机"
                   "${SELF_DIR}"/bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,${project}"]}" -h "${mysql_ip}" -u "root" -p "$BK_MYSQL_ADMIN_PASSWORD"
               fi
            done
            emphasize "register mysql consul on host: ${mysql_ip}"
            reg_consul_svc "${_project_consul["mysql,default"]}" "${_project_port["mysql,default"]}" "${mysql_ip}"
            for project in ${_projects["mysql"]}; do
                    reg_consul_svc "${_project_consul["mysql,${project}"]}" "${_project_port["mysql,${project}"]}" "${mysql_ip}"
            done

            # 中控机配置 default login-path
            emphasize "set mysql ${_project_consul["mysql,default"]} login path on host: 中控机"
            "${SELF_DIR}"/bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,default"]}" -h "${mysql_ip}" -u "root" -p "$BK_MYSQL_ADMIN_PASSWORD"
        emphasize "sign host as module"
        pcmdrc mysql "_sign_host_as_module mysql_master"
    fi

    # 安装slave mysql
    count_slave=$(cat install.config |grep 'mysql(slave)' |wc -l)
    if [ $count_slave -gt 2 ]; then
            echo "mysql(slave)最多支持部署2台。"
            exit 1
    else
            mysql_slave_ip=$(cat install.config | grep 'mysql(slave)' | awk '{print $1}')
            if [ -n "$mysql_slave_ip" ]; then
                    emphasize "install slave_mysql on host:"
                    for ip in ${mysql_slave_ip}; do
                            echo "${ip}"
                    done

                    "${CTRL_DIR}"/pcmd.sh -m mysql_slave "${CTRL_DIR}/bin/install_mysql.sh -n 'default' -P ${_project_port["mysql,default"]} -p '$BK_MYSQL_ADMIN_PASSWORD' -d '${INSTALL_PATH}'/public/mysql -l '${INSTALL_PATH}'/logs/mysql -b \$LAN_IP -i"
                    if [ -n "$mysql_slave_ip" ]; then
                            emphasize "set mysql login path 'default-root' on host:"
                            for ip in ${mysql_slave_ip}; do
                                    echo "${ip}"
                            done
                    fi  
                    # TODO: 使用pcmd时会出现意想不到的bug，可能和tty allocation有关，待定位，临时用原生ssh代替
                    for ip in ${mysql_slave_ip};do
                            ssh "$ip" "$CTRL_DIR/bin/setup_mysql_loginpath.sh -n 'default-root' -h '/var/run/mysql/default.mysql.socket' -u 'root' -p '$BK_MYSQL_ADMIN_PASSWORD'"
                            emphasize "register mysql consul on host:"
                            echo "$ip"
                    done
                    pcmdrc mysql "_sign_host_as_module mysql_slave"
            fi
    fi
}

install_redis_common () {
    _install_redis "$@"
}

_install_redis () {
    local project=$1
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    if [ -z  "${project}" ]; then
        for redis_ip in "${BK_REDIS_IP[@]}"; do
            # 仅redis master节点执行动作
            if [[ $redis_ip == $BK_REDIS_MASTER_IP ]]; then
                emphasize "install redis master on host: ${redis_ip}"
                "${CTRL_DIR}"/pcmd.sh -H "$redis_ip" "'${CTRL_DIR}'/bin/install_redis.sh -n '${_project_name["redis,default"]}' -p '${_project_port["redis,default"]}' -a '${BK_REDIS_ADMIN_PASSWORD}' -b \$LAN_IP"
                emphasize "register ${_project_consul["redis,default"]} on host $redis_ip"
                reg_consul_svc "${_project_consul["redis,default"]}" "${_project_port["redis,default"]}" "${redis_ip}"
                continue
            else
                emphasize "install redis slave on host: ${redis_ip}"
                "${CTRL_DIR}"/pcmd.sh -H "$redis_ip" "'${CTRL_DIR}'/bin/install_redis.sh -n '${_project_name["redis,default"]}' -p '${_project_port["redis,default"]}' -a '${BK_REDIS_ADMIN_PASSWORD}' -b \$LAN_IP"
                emphasize "dont register ${_project_consul["redis,default"]} slave on host $redis_ip"
            fi
            if ! grep "${redis_ip}" "${SELF_DIR}"/bin/02-dynamic/hosts.env | grep -v "CLUSTER" | grep "BK_REDIS_.*_IP_COMM" >/dev/null; then
                "${CTRL_DIR}"/pcmd.sh -H "$redis_ip" "'${CTRL_DIR}'/bin/install_redis.sh -n '${_project_name["redis,default"]}' -p '${_project_port["redis,default"]}' -a '${BK_REDIS_ADMIN_PASSWORD}' -b \$LAN_IP"
                emphasize "register ${_project_consul["redis,default"]} on host $redis_ip"
                # reg_consul_svc "${_project_consul["redis,default"]}" "${_project_port["redis,default"]}" "${redis_ip}"
            fi
        done
    fi
    emphasize "sign host as module"
    pcmdrc redis "_sign_host_as_module redis"
}

install_redis_cluster () {
    local project=$1
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    PORT_LIST=($(sed 's/,/\ /g'<<< ${_project_port["redis_cluster,single"]}))

    if [ -z  "${project}" ]; then
        for redis_ip in "${BK_REDIS_CLUSTER_IP[@]}"; do
            if grep "${redis_ip}" "${SELF_DIR}"/bin/02-dynamic/hosts.env | grep "CLUSTER" | grep "BK_REDIS_.*_IP_COMMA" >/dev/null; then
                "${CTRL_DIR}"/pcmd.sh -H "$redis_ip" "'${CTRL_DIR}'/bin/install_redis_cluster.sh -n '${_project_name["redis_cluster,default"]}' -p '${_project_port["redis_cluster,default"]}' -a '${BK_REDIS_CLUSTER_ADMIN_PASSWORD}' -b \$LAN_IP"
                emphasize "register ${_project_consul["redis_cluster,default"]} on host $redis_ip"
                reg_consul_svc "${_project_consul["redis_cluster,default"]}" "${_project_port["redis_cluster,default"]}" "${redis_ip}"
            fi
        done
    fi

    emphasize "wait for the redis cluster node startup to complete"
    wait_ns_alive redis-cluster.service.consul || fail "redis-cluster.service.consul 无法解析"

    emphasize "create redis cluster on hosts: ${BK_REDIS_CLUSTER_IP[@]}"
    "${CTRL_DIR}"/pcmd.sh -H "$BK_REDIS_CLUSTER_IP0" "echo yes | redis-cli -a $BK_REDIS_CLUSTER_ADMIN_PASSWORD --cluster create $(for host in ${BK_REDIS_CLUSTER_IP[@]}; do echo -n $host:${_project_port["redis_cluster,default"]}\ ; done)"

    # 或者使用 redis-cli --cluster check 进行集群检查 redis-cli --cluster check -a $BK_REDIS_CLUSTER_ADMIN_PASSWORD $BK_REDIS_CLUSTER_IP0:${PORT_LIST[0] 
    # 添加集群马上检查时，这时集群还是处于fail，需要等待一会集群状态才会变成ok
    emphasize "Check the redis cluster status, please wait"
    sleep 10
    "${CTRL_DIR}"/pcmd.sh -H "$BK_REDIS_CLUSTER_IP0" "source ${CTRL_DIR}/functions; response=\$(redis-cli -a \"$BK_REDIS_CLUSTER_ADMIN_PASSWORD\" -h \"$BK_REDIS_CLUSTER_IP0\" -p \"${PORT_LIST[0]}\" cluster info | grep cluster_state | tr -d '[:space:]'); if [[ "\$response" != "cluster_state:ok" ]]; then err "当前集群状态: \$response"; else ok "当前集群状态: \$response"; fi"


    emphasize "sign host as module"
    pcmdrc redis_cluster "_sign_host_as_module redis_cluster"
}

install_rabbitmq () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=rabbitmq
    local port=${_project_port["rabbitmq,default"]}

    if [[ -z ${BK_RABBITMQ_IP_COMMA} ]]; then
        err "rabbitmq 集群数为0"
    else 
        emphasize "install rabbitmq on host: ${BK_RABBITMQ_IP_COMMA}"
        "${CTRL_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_rabbitmq.sh -u '$BK_RABBITMQ_ADMIN_USER' -p '$BK_RABBITMQ_ADMIN_PASSWORD' -d '${INSTALL_PATH}'/public/rabbitmq -l '${INSTALL_PATH}'/logs/rabbitmq"
    fi

    if [[ ${#BK_RABBITMQ_IP[@]} -gt 1 ]]; then
        emphasize "setup rabbitmq cluster on host: ${BK_RABBITMQ_IP_COMMA}"
        "${CTRL_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/setup_rabbitmq_cluster.sh -e '$BK_RABBITMQ_ERLANG_COOKIES'"
        # 重新注册用户，兼容setup rabbitmq cluster 的时候reset 
        "${CTRL_DIR}"/pcmd.sh -H "${BK_RABBITMQ_IP0}" "rabbitmqctl delete_user guest;rabbitmqctl add_user '$BK_RABBITMQ_ADMIN_USER' '$BK_RABBITMQ_ADMIN_PASSWORD';rabbitmqctl set_user_tags '$BK_RABBITMQ_ADMIN_USER' administrator"
    fi

    # 注册consul
    emphasize "register consul ${_project_consul["rabbitmq,default"]} on host: ${BK_RABBITMQ_IP_COMMA}"
    reg_consul_svc "${_project_consul["rabbitmq,default"]}" "${port}" "${BK_RABBITMQ_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_redis_sentinel_common () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local quorum number
    local module=redis_sentinel
    local redis_single_port=$(awk -F ',' '{print $1}' <<<"${_project_port["redis_sentinel,default"]}")
    local redis_sentinel_port=$(awk -F ',' '{print $2}' <<<"${_project_port["redis_sentinel,default"]}")
    local redis_sentinel_consul=${_project_consul["redis_sentinel,default"]}
    local redis_single_passwd=${BK_REDIS_ADMIN_PASSWORD}
    local redis_sentinel_passwd=${BK_REDIS_SENTINEL_PASSWORD}
    local name=${_project_name["redis_sentinel,default"]}

    # 节点数判断
    number=${#BK_REDIS_SENTINEL_IP[@]}
    if [[ "${number}" -gt 1 ]]; then
        quorum=2
    elif [[ "${number}" -eq 0 ]]; then
        err "Install.config 中配置的 Redis Sentinel 节点数为0"
    else
        quorum=1
    fi

    # 部署单实例
    emphasize "install single redis on host: ${BK_REDIS_SENTINEL_IP_COMMA}"
    "${CTRL_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_redis.sh -n '${name}' -p '${redis_single_port}' -a '${redis_single_passwd}' -b \$LAN_IP" || return 1

    # 主从配置
    if [[ "${number}" -ne 1 ]];then
        emphasize "set redis master/slave"
        for node in "${BK_REDIS_SENTINEL_IP[@]}"; do
            if ! [[ $node == "${BK_REDIS_SENTINEL_IP0}" ]]; then
                "${CTRL_DIR}"/pcmd.sh  -H "$node" "redis-cli -a '$redis_single_passwd'  -p '$redis_single_port' -h \$LAN_IP slaveof ${BK_REDIS_SENTINEL_IP[0]} $redis_single_port"
                "${CTRL_DIR}"/pcmd.sh  -H "$node" "redis-cli -a '$redis_single_passwd'  -p '$redis_single_port' -h \$LAN_IP config rewrite"
            fi
        done
    fi

    if ! [[ -z "${BK_REDIS_SENTINEL_PASSWORD}" ]]; then
        emphasize "install redis sentinel on host: ${BK_REDIS_SENTINEL_IP_COMMA} with password ${redis_sentinel_passwd}"
        "${CTRL_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}"/bin/install_redis_sentinel.sh -M ${name} -m $BK_REDIS_SENTINEL_IP0:${redis_single_port} -q "${quorum}" -a ${redis_single_passwd} -b \$LAN_IP -s ${redis_sentinel_passwd}
    else
        emphasize "install redis sentinel on host: ${BK_REDIS_SENTINEL_IP_COMMA} without password"
        "${CTRL_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}"/bin/install_redis_sentinel.sh -M ${name} -m $BK_REDIS_SENTINEL_IP0:${redis_single_port} -q "${quorum}" -b \$LAN_IP -a ${redis_single_passwd}
    fi

    # 注册consul
    emphasize "register consul ${redis_sentinel_consul} on host: ${BK_REDIS_SENTINEL_IP_COMMA}"
    reg_consul_svc "${redis_sentinel_consul}" "${redis_sentinel_port}" "${BK_REDIS_SENTINEL_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_zk () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=zk
    local port=${_project_port["zk,default"]}
    local consul=${_project_consul["zk,default"]}
    # 同步java8安装包
    emphasize "sync java8.tgz  to zk host: ${BK_ZK_IP_COMMA}"
    "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/java8.tgz" "${BK_PKG_SRC_PATH}/"

    # # ZK服务器安装JAVA
    emphasize "install java on host: ${BK_ZK_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_java.sh -p '${INSTALL_PATH}' -f '${BK_PKG_SRC_PATH}'/java8.tgz"
    
    # 部署ZK
    emphasize "install zk on host: ${BK_ZK_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_zookeeper.sh -l '${INSTALL_PATH}' -j '${BK_ZK_IP_COMMA}' -b \$LAN_IP -n '${#BK_ZK_IP[@]}'"

    # 注册consul
    emphasize "register  ${consul} consul server  on host: ${BK_ZK_IP_COMMA} "
    reg_consul_svc "${consul}" "${port}" "${BK_ZK_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_mongodb () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=mongodb
    local port=${_project_port["mongodb,default"]}

    # 批量部署单节点
    emphasize "install mongodb on host: ${BK_MONGODB_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_mongodb.sh -b \$LAN_IP -p '${port}' -d '${INSTALL_PATH}'/public/mongodb -l ${INSTALL_PATH}/logs/mongodb"

    # 根据MONGODB模块数量判断是否安装rs模式
    # 所有模式都为rs模式
    emphasize "Configure MongoDB to RS mode"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/setup_mongodb_rs.sh -a config -e '${BK_MONGODB_KEYSTR_32BYTES}' -j '${BK_MONGODB_IP_COMMA}'"
    "${SELF_DIR}"/pcmd.sh -H "${BK_MONGODB_IP0}" "${CTRL_DIR}/bin/setup_mongodb_rs.sh -a init -j '${BK_MONGODB_IP_COMMA}' -u '$BK_MONGODB_ADMIN_USER' -p '$BK_MONGODB_ADMIN_PASSWORD' -P '${port}'"

    # 注册consul
    for project in ${_projects["mongodb"]}; do
        local consul=${_project_consul["mongodb,${project}"]}
        emphasize "register ${consul} consul server  on host: ${BK_MONGODB_IP_COMMA} "
        reg_consul_svc "${consul}" "${port}" "${BK_MONGODB_IP_COMMA}"
    done
    emphasize "register ${_project_consul["mongodb,default"]} consul server  on host: ${BK_MONGODB_IP_COMMA} "
    reg_consul_svc "${_project_consul["mongodb,default"]}" "${_project_port["mongodb,default"]}" "${BK_MONGODB_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_es7 () {
    local ip
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=es7
    local rest_port=$(awk -F ',' '{print $1}' <<< "${_project_port["es7,default"]}")
    local transport_port=$(awk -F ',' '{print $2}' <<< "${_project_port["es7,default"]}")
    local consul=${_project_consul["es7,default"]}
    if ! [[ ${#BK_ES7_IP[@]} -eq 1 || ${#BK_ES7_IP[@]} -eq 3 ]]; then
        err "es7 节点数量预期为1或3，当前数量为: ${#BK_ES7_IP[@]}"
    fi
    emphasize "install elasticsearch7 on host: ${BK_ES7_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m es7 "$CTRL_DIR/bin/install_es.sh -b \$LAN_IP -s '${BK_ES7_IP_COMMA}' -d '${INSTALL_PATH}/public/elasticsearch' -l '${INSTALL_PATH}/logs/elasticsearch' -P '${rest_port}' -p '${transport_port}'"
    emphasize "elasticsearch7 enable x-pack plugin"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "$CTRL_DIR/bin/setup_es_auth.sh -g"
    set +e
    BK_ES7_ELSE_IP=( $(printf "%s\n" ${BK_ES7_IP[@]}  | grep -vwE "${BK_ES7_IP0// /|}") )
    set -e
    if [[ -z "${BK_ES7_ELSE_IP[*]}" ]]; then
        emphasize "elasticsearch7 enable x-pack plugin"
        "${SELF_DIR}"/pcmd.sh -m es7 "$CTRL_DIR/bin/setup_es_auth.sh -g;$CTRL_DIR/bin/setup_es_auth.sh -a"
    else
        emphasize "elasticsearch7 enable x-pack plugin on host: ${BK_ES7_IP0}"
        "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "$CTRL_DIR/bin/setup_es_auth.sh -a"
        emphasize "sync elastic-certificates to host: $LAN_IP"
        rsync -ao "${BK_ES7_IP0}":/etc/elasticsearch/elastic-certificates.p12 "${INSTALL_PATH}"/cert/elastic-certificates.p12
        for ip in "${BK_ES7_ELSE_IP[@]}"; do
            emphasize "sync elastic-certificates to host: ${ip}" 
            rsync -ao "${INSTALL_PATH}"/cert/elastic-certificates.p12 "${ip}":/etc/elasticsearch/elastic-certificates.p12
            emphasize "chown elastic-certficates on host: ${ip}" 
            "${SELF_DIR}"/pcmd.sh -H "${ip}" "chown elasticsearch:elasticsearch /etc/elasticsearch/elastic-certificates.p12"
            emphasize "elasticsearch7 enable x-pack plugin on host: ${ip}"
            "${SELF_DIR}"/pcmd.sh -H "${ip}" "$CTRL_DIR/bin/setup_es_auth.sh -a"
        done
    fi
    emphasize "elasticsearch7 change paaword"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "source ${CTRL_DIR}/functions;wait_port_alive '${rest_port}' 50;$CTRL_DIR/bin/setup_es_auth.sh -s -b \$LAN_IP -p '$BK_ES7_ADMIN_PASSWORD'"
    # 注册consul
    emphasize "register  ${consul} consul server  on host: ${BK_ES7_IP_COMMA} "
    reg_consul_svc "${consul}" "${rest_port}" "${BK_ES7_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    # 加入es清理
    if ! "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "grep 'es_delete_expire' /var/spool/cron/root" >/dev/null 2>&1;then
    "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "echo '00 01 * * * $CTRL_DIR/bin/es_delete_expire_index.sh http://$BK_MONITOR_ES7_HOST:9200 paas_app_log- 30' >> /var/spool/cron/root"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "echo '01 01 * * * $CTRL_DIR/bin/es_delete_expire_index.sh http://$BK_MONITOR_ES7_HOST:9200 esb_api_log_community- 30'  >> /var/spool/cron/root"
    emphasize "加入es索引清理计划,30天"
    fi
}


install_influxdb () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=influxdb
    local port=${_project_port["influxdb,default"]}
    local consul=${_project_consul["influxdb,default"]}

    emphasize "install influxdb on host: ${BK_INFLUXDB_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "${CTRL_DIR}/bin/install_influxdb.sh -b \$LAN_IP -P '${port}'  \
                    -d '${INSTALL_PATH}/public/influxdb' -l '${INSTALL_PATH}/logs/influxdb' -w '${INSTALL_PATH}/public/influxdb/wal' -p '${BK_INFLUXDB_ADMIN_PASSWORD}' -u admin"

    # 注册consul
    emphasize "register  ${consul} consul server  on host: ${BK_INFLUXDB_IP_COMMA} "
    reg_consul_svc "${consul}" "${port}" "${BK_INFLUXDB_IP_COMMA}"
   
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_license () {
    local module=license
    local port=8443

    emphasize "install license on host: ${BK_LICENSE_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "${CTRL_DIR}/bin/install_license.sh -b \$LAN_IP -e '${CTRL_DIR}'/bin/04-final/license.env -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}'"

    # 注册consul
    emphasize "register  license consul server  on host: ${BK_LICENSE_IP_COMMA} "
    reg_consul_svc "${module}" "${port}" "${BK_LICENSE_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_cert () {
    local module=cert
    "${SELF_DIR}"/pcmd.sh -m ALL "rsync -a ${BK_PKG_SRC_PATH}/cert/  ${INSTALL_PATH}/cert/ && chown blueking.blueking -R ${INSTALL_PATH}/cert/"
}

install_iam () { 
    local module=iam
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    emphasize "migrate $module sql"
    migrate_sql ${module}
    for project in ${_projects[@]}; do
        emphasize "install ${target_name}-${project} on host: ${BK_IAM_IP_COMMA}"
        local port=${_project_port["${target_name},${project}"]}
        local consul=${_project_consul["${target_name},${project}"]}
        "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_bkiam.sh -b \$LAN_IP -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -e '${CTRL_DIR}/bin/04-final/bkiam.env'"
        emphasize "register  ${consul} consul server  on host: ${BK_IAM_IP_COMMA}"
        reg_consul_svc "${consul}" "${port}" "${BK_IAM_IP_COMMA}"
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_iam_search_engine () { 
    local module=iam_search_engine
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    for project in ${_projects[@]}; do
        emphasize "install ${target_name}-${project} on host: ${BK_IAM_SEARCH_ENGINE_IP_COMMA}"
        local port=${_project_port["${target_name},${project}"]}
        local consul=${_project_consul["${target_name},${project}"]}
        "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_bkiam_search_engine.sh -b \$LAN_IP -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -e '${CTRL_DIR}/bin/04-final/bkiam_search_engine.env'"
        emphasize "register  ${consul} consul server  on host: ${BK_IAM_SEARCH_ENGINE_IP_COMMA}"
        reg_consul_svc "${consul}" "${port}" "${BK_IAM_SEARCH_ENGINE_IP_COMMA}"
    done

    emphasize "add or update appocode ${BK_IAM_SAAS_APP_CODE}"
    add_or_update_appcode "$BK_IAM_SAAS_APP_CODE" "$BK_IAM_SAAS_APP_SECRET"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_ssm () {
    local module=ssm
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}
    emphasize "migrate $module sql"
    migrate_sql $module
    for project in ${projects[@]}; do
        emphasize "install ${target_name}-${project} on host: ${BK_SSM_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -H "${_project_ip["${target_name},${project}"]}" \
                 "${CTRL_DIR}/bin/install_bkssm.sh -e '${CTRL_DIR}/bin/04-final/bkssm.env' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -b \$LAN_IP"
        emphasize "register  ${consul} consul server  on host: ${BK_SSM_IP_COMMA}"
        reg_consul_svc "${_project_consul[${target_name},${project}]}"  "${_project_port[${target_name},${project}]}"  "${_project_ip[${target_name},${project}]}"
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_auth () {
    local module=auth
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}

    emphasize "migrate $module sql"
    migrate_sql $module
    for project in ${projects[@]}; do
        emphasize "install ${target_name}-${project} on host: ${BK_AUTH_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -H "${_project_ip["${target_name},${project}"]}" \
                 "${CTRL_DIR}/bin/install_bkauth.sh -e '${CTRL_DIR}/bin/04-final/bkauth.env' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -b \$LAN_IP"
        emphasize "register  ${consul} consul server  on host: ${BK_AUTH_IP_COMMA}"
        reg_consul_svc "${_project_consul[${target_name},${project}]}"  "${_project_port[${target_name},${project}]}"  "${_project_ip[${target_name},${project}]}"
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_monstache () {
    local module=monstache
    "${SELF_DIR}"/pcmd.sh -m cmdb "bash ${CTRL_DIR}/bin/install_monstache.sh"
    log "渲染cmdb"
    sed -i.bak 's/fullTextSearch: "off"/fullTextSearch: "on"/' $BK_PKG_SRC_PATH/cmdb/support-files/templates/server#conf#common.yaml
    ./bkcli sync cmdb
    ./bkcli render cmdb

    log "重启cmdb"
    ./bkcli restart cmdb

    log "检查cmdb"
    ./bkcli check cmdb
}

install_cmdb () {
    _install_cmdb_project "$@"
}

_install_cmdb_project () {
    local module=cmdb
    local project=$1
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}

    emphasize "grant mongodb privilege for ${module}"
    grant_mongodb_pri ${module} 
    grant_mongodb_pri cmdb_events

    emphasize "add or update appocode ${BK_CMDB_APP_CODE}"
    add_or_update_appcode "$BK_CMDB_APP_CODE" "$BK_CMDB_APP_SECRET"

    if [[ -z ${project} ]]; then
        emphasize "install ${module} on host: $module"
        "${SELF_DIR}"/pcmd.sh -m "${module}" \
                "${CTRL_DIR}/bin/install_cmdb.sh -e '${CTRL_DIR}/bin/04-final/cmdb.env' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -l '${INSTALL_PATH}/logs/cmdb'"
    else
        # 后续cmdb原子脚本支持分模块部署的时候可走这个逻辑
        for project in ${project[@]}; do
            emphasize "install ${module}-${project} on host: $module"
            "${SELF_DIR}"/pcmd.sh -H "${_project_ip["${target_name},${project}"]}" \
                     "${CTRL_DIR}/bin/install_cmdb.sh -e '${CTRL_DIR}/bin/04-final/cmdb.env' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -m '${project}'"
        done
    fi
    emphasize "start bk-cmdb.target on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "systemctl start bk-cmdb-admin.service"
    sleep 10
    "${SELF_DIR}"/pcmd.sh -m "${module}" "systemctl start bk-cmdb.target"
    for project in ${projects[@]}; do
        # consul服务注册排除掉cmdb
        if ! [[ ${project} == "synchronize" ]]; then
            emphasize "register consul  ${project} on host:${_project_ip[${target_name},${project}]} "
            reg_consul_svc "${_project_consul[${target_name},${project}]}"  "${_project_port[${target_name},${project}]}"  "${_project_ip[${target_name},${project}]}"
        fi
    done
    if [[ -n $BK_AUTH_IP_COMMA ]]; then
        emphasize "sync open_paas data to bkauth"
        sync_secret_to_bkauth
    fi
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}


install_paas () {
    _install_paas_project "$@"
}

_install_paas_project () {
    local module=paas
    local project=${1:-all}
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects["${module}"]}
    if [ "$project" == 'all' ];then project="${projects[@]}";fi
    # 创建paas相关数据库
    emphasize "migrate ${module} sql"
    migrate_sql $module
    # paas服务器同步并安装python
    emphasize "sync and install python on host: ${BK_PAAS_IP_COMMA}"
    install_python $module

    # 要加判断传入值是否正确
    for project in ${project[@]}; do
        python_path=$(get_interpreter_path "paas" "paas")
        project_port=${_project_port["${target_name},${project}"]}
        project_consul=${_project_consul["${target_name},${project}"]}
        for ip in "${BK_PAAS_IP[@]}"; do 
            emphasize "install ${module}(${project}) on host: ${ip}"
            cost_time_attention
            "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_paas.sh -e '${CTRL_DIR}/bin/04-final/paas.env' -m '$project' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -b \$LAN_IP --python-path '${python_path}'"
            emphasize "register consul ${project_consul} on host: ${ip}"
            reg_consul_svc "${project_consul}" "${project_port}" "$ip"
        done
    done

    # 注册白名单
    emphasize "add or update appcode: $BK_PAAS_APP_CODE"
    add_or_update_appcode "$BK_PAAS_APP_CODE" "$BK_PAAS_APP_SECRET"
    add_or_update_appcode "bk_console" "$BK_PAAS_APP_SECRET"
    add_or_update_appcode bk_monitorv3 bk_monitorv3

    # 注册权限模型
    emphasize "Registration authority model for ${module}"
    bkiam_migrate $module

    # 挂载nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "mount nfs to host: $BK_NFS_IP0"
        pcmdrc ${module} "_mount_shared_nfs open_paas"
    fi

    # 版本信息
    _update_common_info

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_etcd () {
    local module=etcd
    #local etcd_version=v3.5.4
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)

    emphasize "sync cfssl&cfssljson commands to /usr/local/bin/"
    #"${SELF_DIR}"/pcmd.sh -m ${module} "rsync -a ${BK_PKG_SRC_PATH}/etcd-${etcd_version}-linux-amd64/{etcd,etcdctl,etcdutl} /usr/local/bin/"
    rsync -a "${CTRL_DIR}"/{cfssl,cfssljson} /usr/local/bin/ && chmod +x /usr/local/bin/{cfssljson,cfssl}

    # 生成 etcd 证书
    emphasize "generate etcd cert"
    ${CTRL_DIR}/bin/gen_etcd_certs.sh -p "${INSTALL_PATH}"/cert/etcd -i "${BK_ETCD_IP[*]}" ; chown -R blueking.blueking "${INSTALL_PATH}"/cert/etcd
    "${SELF_DIR}"/sync.sh ${module} "${INSTALL_PATH}"/cert/etcd "${INSTALL_PATH}"/cert/
    "${SELF_DIR}"/sync.sh ${module} "$HOME"/.cfssl/ "$HOME"/

    emphasize "install ${module} on host: ${BK_ETCD_IP[@]}"
    "${SELF_DIR}"/pcmd.sh -m ${module} "export ETCD_CERT_PATH=${INSTALL_PATH}/cert/etcd;export ETCD_DATA_DIR=${INSTALL_PATH}/public/etcd;export PROTOCOL=https;${CTRL_DIR}/bin/install_etcd.sh ${BK_ETCD_IP[*]}"

    # 注册 consul
    for ip in "${BK_ETCD_IP[@]}"; do
        emphasize "register consul ${module} on host: $ip"
        reg_consul_svc "${_project_consul["${module},default"]}" "${_project_port["${module},default"]}" "$ip"
    done
}
install_apisix () {
    local module=apisix
    emphasize "install apix on host: apigw"
    "${SELF_DIR}"/pcmd.sh -m apigw "${CTRL_DIR}/bin/install_apisix.sh -p ${INSTALL_PATH}" 
}

install_apigw_fe () {
    local module=apigw
    local target_name=$(map_module_name $module)

    emphasize "create directories ..."
    "${SELF_DIR}"/pcmd.sh -H "${BK_NGINX_IP_COMMA}" "install -o blueking -g blueking -m 755 -d  '${INSTALL_PATH}/bk_apigateway'"

    emphasize "install apigw frontend on host: ${BK_NGINX_IP_COMMA}"
    PRSYNC_EXTRA_OPTS="--delete" "${SELF_DIR}"/sync.sh nginx "${BK_PKG_SRC_PATH}/${target_name}/dashboard-fe/" "${INSTALL_PATH}/bk_apigateway/dashboard-fe/"
    ## 兼容control机器部署nginx的情况
    if [[ -d "${INSTALL_PATH}/bk_apigateway" ]]; then
        /usr/bin/cp -rf ${BK_PKG_SRC_PATH}/${target_name}/dashboard-fe "${INSTALL_PATH}/bk_apigateway/"
        chown -R blueking.blueking "${INSTALL_PATH}/bk_apigateway/"
    fi
    "${SELF_DIR}"/pcmd.sh -m nginx "${CTRL_DIR}/bin/render_tpl -p ${INSTALL_PATH} -m ${target_name} -e ${CTRL_DIR}/bin/04-final/bkapigw.env ${BK_PKG_SRC_PATH}/bk_apigateway/support-files/templates/dashboard-fe#static#runtime#runtime.js"

}


install_apigw () {
    local module=apigw
    local project=${1:-all}
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects["${module}"]}

    # 部署前端
    install_apigw_fe

    # 创建 apigw 相关数据库
    emphasize "migrate ${module} sql"
    migrate_sql $module

    # apigw 服务器同步并安装python
    emphasize "sync and install python on host: ${BK_APIGW_IP_COMMA}"
    install_python $module

    for project in dashboard bk-esb operator apigateway apigateway-core-api; do
        emphasize "register consul $project on host: ${ip}"
        reg_consul_svc ${_project_consul["${module},${project}"]} ${_project_port["${module},${project}"]} "${BK_APIGW_IP_COMMA}"
    done

    # 安装 apigw
    for ip in "${BK_APIGW_IP_COMMA[@]}"; do 
        emphasize "install bk-apigateway on host: ${ip}"
        cost_time_attention
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bkapigw.sh -b \$LAN_IP -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' --cert-path '${INSTALL_PATH}/cert/etcd' -e '${CTRL_DIR}/bin/04-final/bkapigw.env'"
    done

    emphasize "add or update appocode ${BK_APIGW_APP_CODE}"
    add_or_update_appcode "$BK_APIGW_APP_CODE" "$BK_APIGW_APP_SECRET"
    add_or_update_appcode bk_apigw_test "$BK_APIGW_TEST_APP_SECRET"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module apigateway"
}

install_python () {
    local module=$1
    local py_pkgs=(py27.tgz py36.tgz py27_e.tgz py36_e.tgz)
    local target_dir=/opt
    local target_ip="BK_${module^^}_IP[@]"
    # 同步python安装包到目标目录或目标服务器
    if ! [[ -z $module ]]; then
        for ip in ${!target_ip}; do 
            # 安装其他服务器python包
            if  "${SELF_DIR}"/pcmd.sh -H "${ip}" "grep -w 'python' ${INSTALL_PATH}/.installed_module  || echo "PYTHON_UNINSTALL"" | grep "PYTHON_UNINSTALL" >/dev/null 2>&1; then
                "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/python" "${BK_PKG_SRC_PATH}/" || err "同步PYTHON包失败"
                for pkg in "${py_pkgs[@]}"; do
                    "${SELF_DIR}"/pcmd.sh -H "${ip}"  "tar xf ${BK_PKG_SRC_PATH}/python/$pkg -C $target_dir/"
                done
                "${SELF_DIR}"/pcmd.sh -H "${ip}"  "[ -f ${INSTALL_PATH}/.installed_module ] || touch ${INSTALL_PATH}/.installed_module;echo 'python' >>${INSTALL_PATH}/.installed_module"
            else
                emphasize "skip install python on host: ${ip}"
            fi
        done
    else
        # 安装中控机python包
        for pkg in "${py_pkgs[@]}"; do
            emphasize "install python on host: $LAN_IP"
            "${SELF_DIR}"/pcmd.sh -H "$LAN_IP"  "tar xf ${BK_PKG_SRC_PATH}/python/$pkg -C $target_dir/"
        done
    fi
}

install_node () {
    local module="${1:-lesscode}"
    local pkg=$(_find_node_latest)
    local target_dir="/opt/${pkg%.tar.gz}"
    if [[ -z "${BK_PKG_SRC_PATH}"/"${pkg}" ]]; then
        err "Node js package not find"
    fi
    emphasize "sync node package to module: $module"
    "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/$pkg" "${BK_PKG_SRC_PATH}/" || err "同步Node包失败"
    emphasize "unpack node package to directory: $target_dir"
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "tar xf ${BK_PKG_SRC_PATH}/$pkg -C /opt" 
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "chown -R blueking.blueking ${target_dir}"
    pcmdrc "${module}" "[[ -f '${target_dir}'/bin/node ]] || err '${target_dir}'/bin/node not exist"
    emphasize "Link ${target_dir}/bin/node to /usr/bin/node"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "ln -sf  '${target_dir}'/bin/node /usr/bin/node"
    emphasize "Link ${target_dir}/bin/npm to /usr/bin/npm"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "ln -sf  '${target_dir}'/bin/npm /usr/bin/npm"
}

install_consul_template () {
    local module=consul_template
    local install_module=$1
    local install_ip=$2
    emphasize "install consul template on host: ${install_ip}"
    "${SELF_DIR}"/pcmd.sh -H "${install_ip}"  "${CTRL_DIR}/bin/install_consul_template.sh -m ${install_module}"
    emphasize "start and reload consul-template on host: ${install_ip}"
    # 启动后需要reload，防止这台ip已经启动过consul-template，如果不reload，没法生效新安装的子配置
    "${SELF_DIR}"/pcmd.sh -H "${install_ip}" "systemctl start consul-template; sleep 1; systemctl reload consul-template"
}

install_nginx () {
    local module=nginx

    # 安装openresty
    emphasize "install openresty  on host: ${BK_NGINX_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"

    # nginx 服务器上安装consul-template
    emphasize "install consul-template  on host: ${BK_NGINX_IP_COMMA}"
    install_consul_template ${module} "${BK_NGINX_IP_COMMA}"

    # 注册paas.service.consul cmdb.service.consul job.service.consul
    #if [[ $BK_HTTP_SCHEMA == 'http' ]]; then 
    #   port=80
    #else
    #    port=443
    #fi
    # 此处应为paas.service.consul的内网paas端口，支持自定义
    port=${BK_PAAS_PRIVATE_ADDR##*:}
    for name in paas cmdb job; do
        emphasize "register consul service -> {${name}} on host ${BK_NGINX_IP_COMMA} "
        reg_consul_svc $name $port "${BK_NGINX_IP_COMMA}"
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc ${module} "_sign_host_as_module consul-template"
}

install_appo () {
    local module=appo
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    if ! [ -z "${BK_APPT_IP_COMMA}" ]; then
        if is_string_in_array "${BK_APPT_IP_COMMA}" "${BK_APPO_IP[@]}"; then
            err "appo appt 不可部署在同一台服务器"
        fi
    fi
    emphasize "install docker on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_docker_for_paasagent.sh -v $PLAT_VER"

    emphasize "install ${module} on host: ${module}"
    cost_time_attention
    "${SELF_DIR}"/pcmd.sh -m ${module} \
            "${CTRL_DIR}/bin/install_paasagent.sh -e ${CTRL_DIR}/bin/04-final/paasagent.env -b \$LAN_IP -m prod -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"

    # 安装openresty
    emphasize "install openresty on host: ${BK_APPO_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"
    
    emphasize "install consul-template on host: ${BK_APPO_IP_COMMA}"
    install_consul_template "paasagent" "${BK_APPO_IP_COMMA}"

    # nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "mount nfs to host: $BK_NFS_IP0"
        pcmdrc ${module} "_mount_shared_nfs ${module}"
    fi

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc ${module} "_sign_host_as_module consul-template"
}

install_appt () {
    local module=appt
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    if is_string_in_array "${BK_APPT_IP_COMMA}" "${BK_APPO_IP[@]}"; then
        err "appo appt 不可部署在同一台服务器"
    fi
    emphasize "install docker on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_docker_for_paasagent.sh -v $PLAT_VER"

    emphasize "install ${module} on host: ${module}"
    cost_time_attention
    "${SELF_DIR}"/pcmd.sh -m ${module} \
            "${CTRL_DIR}/bin/install_paasagent.sh -e ${CTRL_DIR}/bin/04-final/paasagent.env -b \$LAN_IP -m test -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"

    # 安装openresty
    emphasize "install openresty on host: ${BK_APPT_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"

    emphasize "install consul template on host: ${BK_APPT_IP_COMMA}"
    install_consul_template "paasagent" "${BK_APPT_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc ${module} "_sign_host_as_module consul-template"
}

install_job () {
    local module=$1
    case  "$module" in
        backend)
        _install_job_backend "$@"
        ;;
        frontend)
        _install_job_frontend
        ;;
        *)
        _install_job_backend 
        _install_job_frontend
        ;;
    esac
}

_install_job_frontend () {
    emphasize "create directories ..."
    "${SELF_DIR}"/pcmd.sh -H "${BK_NGINX_IP_COMMA}" "install -o blueking -g blueking -m 755 -d  '${INSTALL_PATH}/job'"
    emphasize "install job frontend on host: ${BK_NGINX_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_NGINX_IP_COMMA}" "${CTRL_DIR}/bin/release_job_frontend.sh -p ${INSTALL_PATH} -B ${BK_PKG_SRC_PATH}/backup -s ${BK_PKG_SRC_PATH}/ -i $BK_JOB_API_PUBLIC_URL"
}

_install_job_backend () {
    local module=job
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}
    for m in job_backup job_manage job_crontab job_execute job_analysis;do 
        # 替换_ 兼容projects.yaml 格式
        # mongod  joblog用户相关授权已经在install mongodb的时候做过
        emphasize "grant rabbitmq private for ${module}"
        grant_rabbitmq_pri ${m} "${BK_JOB_IP_COMMA}"
    done
    # esb app_code
    emphasize "add or update appcode: ${BK_JOB_APP_CODE}"
    add_or_update_appcode "$BK_JOB_APP_CODE" "$BK_JOB_APP_SECRET"
    # 导入sql
    emphasize "migrate sql for module: ${module}"
    migrate_sql ${module}

    emphasize "sync yq commands to /usr/local/bin/"
    _install_yq ${module}
    # job依赖java环境
    ${SELF_DIR}/pcmd.sh -H ${BK_JOB_IP_COMMA} "if ! which java >/dev/null;then ${CTRL_DIR}/bin/install_java.sh -p ${INSTALL_PATH} -f ${BK_PKG_SRC_PATH}/java8.tgz;fi"

    # mongod用户授权
    emphasize "grant mongodb privilege for ${module}"
    mongo_args=$(awk -F'[:@/?]' '{printf "-u '%s' -p '%s' -d '%s'", $1, $2, $5}' <<<"${BK_JOB_LOGSVR_MONGODB_URI##mongodb://}")
    BK_MONGODB_ADMIN_PASSWORD=$(urlencode "${BK_MONGODB_ADMIN_PASSWORD}") # 兼容密码存在特殊字符时的URL编码

    "${SELF_DIR}"/pcmd.sh -H "${BK_MONGODB_IP0}" "${CTRL_DIR}/bin/add_mongodb_user.sh -i mongodb://$BK_MONGODB_ADMIN_USER:$BK_MONGODB_ADMIN_PASSWORD@\$LAN_IP:27017/admin $mongo_args"
    # 单台部署全部
    emphasize "install ${module} on host: ${BK_JOB_IP_COMMA}}"
    cost_time_attention
    ${SELF_DIR}/pcmd.sh -H ${BK_JOB_IP_COMMA} "${CTRL_DIR}/bin/install_job.sh -e ${CTRL_DIR}/bin/04-final/job.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    emphasize "start bk-${module}.target on host: ${BK_JOB_IP_COMMA}"
    cost_time_attention "bk-job.target takes a while to fully boot up, please wait!"
    ${SELF_DIR}/pcmd.sh -H ${BK_JOB_IP_COMMA} "systemctl start bk-job.target"

    # 检查
    emphasize "${module} health check"
    wait_return_code "${module}" 120 || err "job 健康检查失败 请重新启动"

    # 权限模型
    emphasize "Registration authority model for ${module}"
    bkiam_migrate ${module}

    # nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "mount nfs to host: ${BK_NFS_IP0}"
        pcmdrc job "_mount_shared_nfs job"
    fi
	
    if [[ -n $BK_AUTH_IP_COMMA ]]; then
        emphasize "sync open_paas data to bkauth"
        sync_secret_to_bkauth
    fi

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_usermgr () {
    local module=usermgr
    local target_name=$(map_module_name $module)
    emphasize "migrate ${module} sql"
    migrate_sql $module
    emphasize "grant rabbitmq private for ${module}"
    grant_rabbitmq_pri $module
    emphasize "sync and install python on host: ${BK_USERMGR_IP_COMMA}"
    install_python $module

    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}
    for project in ${projects[@]}; do
        local python_path=$(get_interpreter_path ${module} "${project}")
        for ip in "${BK_USERMGR_IP[@]}"; do
            emphasize "install ${module} ${project} on host: ${BK_USERMGR_IP_COMMA} "
            "${SELF_DIR}"/pcmd.sh -H "${ip}" \
                     "${CTRL_DIR}/bin/install_usermgr.sh -e ${CTRL_DIR}/bin/04-final/usermgr.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH} --python-path ${python_path}"
            reg_consul_svc "${_project_consul[${target_name},${project}]}" "${_project_port[${target_name},${project}]}" "${ip}"
        done
    done

    emphasize "add or update appcode: ${BK_USERMGR_APP_CODE}"
    # 注册app_code
    add_or_update_appcode "$BK_USERMGR_APP_CODE" "$BK_USERMGR_APP_SECRET"
    emphasize "Registration authority model for ${module}"
    # 注册权限模型
    bkiam_migrate ${module}

    if [[ -n $BK_AUTH_IP_COMMA ]]; then
        emphasize "sync open_paas data to bkauth"
        sync_secret_to_bkauth
    fi
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_saas-o () {
    install_saas appo "$@"
}

install_saas-t () {
    install_saas appt "$@"
}

install_saas () {
    local env=${1:-appo}
    local app_code=$2
    local servers=${3:-$BK_APPO_IP_COMMA}
    local app_version=$4

    source "${SELF_DIR}"/.rcmdrc

    if [ $# -ne 0 ]; then
        if [ "$app_version" == "" ]; then
            emphasize "未指定版本号，默认部署最新版本"
            pkg_name=$(_find_latest_one $app_code)
        else
            pkg_name=$(_find_saas ${app_code})
        fi

        if [ -z "$pkg_name" ];
        then
            fail "未找到 $app_code 对应的 S-mart 包，请检查 ${BK_PKG_SRC_PATH}/official_saas/ 下是否有对应的介质"
        fi

        emphasize "开始部署 $app_code:"
        emphasize "部署介质: $pkg_name"
        emphasize "MD5 校验: $(md5sum ${BK_PKG_SRC_PATH}/official_saas/${pkg_name} |awk '{print $1}')"
        emphasize "部署服务器: $servers"
        _install_saas $env $app_code $pkg_name $servers
        assert " SaaS  $app_code 部署成功" "SaaS $app_code 部署失败."
        set_console_desktop ${app_code}
    else
        all_app=( $(_find_all_saas) )
        if [ ${#all_app[@]} -eq 0 ]; then
            fail "no saas package found"
        fi

        for app_code in $(_find_all_saas); do
            emphasize "开始部署 $app_code:"
            emphasize "部署介质: $pkg_name"
            emphasize "MD5 校验: $(md5sum ${BK_PKG_SRC_PATH}/official_saas/${pkg_name} |awk '{print $1}')"
            emphasize "部署服务器: $servers"
            _install_saas "$env" "$app_code" $(_find_latest_one "$app_code") $servers
            assert " SaaS  $app_code 部署成功" "SaaS $app_code 部署失败."
            if [[ -n $BK_AUTH_IP_COMMA ]]; then
                emphasize "sync open_paas data to bkauth"
                sync_secret_to_bkauth
            fi
            set_console_desktop ${app_code}
        done
    fi
}


_install_saas () {
    local app_env=$1
    local app_code=$2
    local pkg_name=$3
    local app_servers=$4



    # 解包，导入 SaaS 中的 deploy/
    if [ -f "$BK_PKG_SRC_PATH"/official_saas/"$pkg_name" ];
    then
        # 是否带 deploy/ 目录
        if tar -tf "$BK_PKG_SRC_PATH"/official_saas/"$pkg_name" |grep  "${app_code}/deploy/env.yml" > /dev/null ;
        then
            step "存在 deploy/ 目录，开始导入 SaaS 环境变量"

            tar xf "$BK_PKG_SRC_PATH"/official_saas/"$pkg_name" -C /tmp/ ${app_code}/app.yml ${app_code}/deploy/

            log "导出备份当前变量"
            /opt/py36/bin/python ${CTRL_DIR}/bin/add_saas_env/main.py \
                -a /tmp/${app_code}/app.yml \
                -e /tmp/${app_code}/deploy/env.yml \
                -p ${CTRL_DIR}/bin/01-generate,${CTRL_DIR}/bin/02-dynamic,${CTRL_DIR}/bin/04-final,${CTRL_DIR}/bin/05-canway \
                --export-only

            log "导入 deploy/ 中定义的变量"
            /opt/py36/bin/python ${CTRL_DIR}/bin/add_saas_env/main.py \
                -a /tmp/${app_code}/app.yml \
                -e /tmp/${app_code}/deploy/env.yml \
                -p ${CTRL_DIR}/bin/01-generate,${CTRL_DIR}/bin/02-dynamic,${CTRL_DIR}/bin/04-final,${CTRL_DIR}/bin/05-canway
        fi


        # 不需要判断版本，按目录顺序，文件名顺序进行执行 sql 即可
        # 导入 SQL
        # 按目录名正序
        set +e
        if [ -d "/tmp/${app_code}/deploy/sql/" ];
        then
            for sqlDir in $(ls -trh /tmp/${app_code}/deploy/sql/ | awk '{print $NF}' |sort -k1.1n);
            do
                # 按文件名正序
                for sql in $(ls -trh /tmp/${app_code}/deploy/sql/${sqlDir}/ |sort -k1.1n);
                do
                    # 判断是否有导入
                    if [ ! -f ~/.migrate/${app_code}_${sqlDir}_${sql} ];
                    then
                        log "开始导入 ${sqlDir}/${sql}"
                        if mysql --login-path=mysql-paas < /tmp/${app_code}/deploy/sql/${sqlDir}/${sql} >/dev/null;
                        then 
                            touch ~/.migrate/${app_code}_${sqlDir}_${sql}
                            log "导入成功"
                        else
                            err "导入失败"
                        fi
                    else
                        log  "$(green_echo '[跳过]') ${sqlDir}/${sql} 曾经导入过。"
                    fi
                done
            done
        fi
        set -e
        # ^导入 SQL

    else
        err "未找到 $BK_PKG_SRC_PATH"/official_saas/"$pkg_name, 请确认包是否存在"
    fi
    # ^deploy/ 处理

    if [[ "$app_code" != "" ]];
    then
        # 清理部署时产生的临时文件
        rm -rf /tmp/${app_code}/
    fi

    step "添加应用白名单"
    _add_saas_skip_auth $app_code

    step "开始部署 SaaS $app_code"
    /opt/py36/bin/python "${SELF_DIR}"/bin/saas.py \
        -e "$app_env" \
        -n "$app_code" \
        -k "$BK_PKG_SRC_PATH"/official_saas/"$pkg_name" \
        -f "$CTRL_DIR"/bin/04-final/paas.env \
        -s $app_servers
}

install_bkmonitorv3 () {
    _install_bkmonitor "$@"
}

_install_bkmonitor () {
    local module=monitorv3
    local project=$1
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    projects=${_projects[${module}]}
    if ! [[ -z "${project}" ]]; then 
        projects=$project
    fi
    emphasize "migrate $module sql"
    migrate_sql $module
    emphasize "grant rabbitmq private for ${module}"
    grant_rabbitmq_pri $module
    emphasize "install python on host: ${module}"
    install_python $module

    # 注册app_code
    emphasize "add or update appcode ${BK_MONITOR_APP_CODE}"
    add_or_update_appcode "$BK_MONITOR_APP_CODE" "$BK_MONITOR_APP_SECRET"
    add_or_update_appcode bk_monitorv3 bk_monitorv3

    for project in ${projects[@]}; do
        IFS="," read -r -a target_server<<<"${_project_ip["${target_name},${project}"]}"
        for ip in ${target_server[@]}; do
            python_path=$(get_interpreter_path $module "$project")
            emphasize "install ${module} ${project} on host: ${ip}"
            cost_time_attention
            if [[ ${python_path} =~ "python" ]]; then
                "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bkmonitorv3.sh -b \$LAN_IP -m ${project} --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/bkmonitorv3.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
            else
                "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bkmonitorv3.sh -b \$LAN_IP -m ${project}  -e ${CTRL_DIR}/bin/04-final/bkmonitorv3.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
            fi
            emphasize "sign host as module"
            pcmdrc "${ip}" "_sign_host_as_module ${module}_${project}"
        done
        if grep -w -E -q "grafana|unify-query" <<< "${project}"; then
           emphasize "register ${_project_consul[${target_name},${project}]} consul on host: ${_project_ip[${target_name},${project}]}"
           reg_consul_svc ${_project_consul[${target_name},${project}]}  ${_project_port[${target_name},${project}]} ${_project_ip[${target_name},${project}]}
        fi

    done

    ## 处理监控平台兼容gse 1.0
    tmp_gv=$(echo $gse_version | grep -oP '(\d+.)' | tr -d "\n")
    if [[ $tmp_gv < 2.0 ]]; then
        mysql -h $BK_MONITOR_MYSQL_HOST -u $BK_MONITOR_MYSQL_USER -p$BK_MONITOR_MYSQL_PASSWORD -P $BK_MONITOR_MYSQL_PORT -e \
            "update bkmonitorv3_alert.global_setting set value='false' where \`key\`='USE_GSE_AGENT_STATUS_NEW_API' and value='true';"
    fi

    if [[ -n $BK_AUTH_IP_COMMA ]]; then
        emphasize "sync open_paas data to bkauth"
        sync_secret_to_bkauth
    fi
}

install_paas_plugins () {
    local module=paas_plugins
    local python_path=/opt/py27/bin/python
    emphasize "sync java11 on host: ${BK_PAAS_IP_COMMA}"
    "${SELF_DIR}"/sync.sh "paas" "${BK_PKG_SRC_PATH}/java11.tgz" "${BK_PKG_SRC_PATH}/"

    emphasize "install java11 on host: ${BK_PAAS_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "paas" "mkdir ${INSTALL_PATH}/jvm/;tar -xf ${BK_PKG_SRC_PATH}/java11.tgz --strip-component=1 -C ${INSTALL_PATH}/jvm/"
 
    if [[ -n $BK_APIGW_IP_COMMA ]]; then
        emphasize "sync java11 on host: ${BK_APIGW_IP_COMMA}"
        "${SELF_DIR}"/sync.sh "apigw" "${BK_PKG_SRC_PATH}/java11.tgz" "${BK_PKG_SRC_PATH}/"
        emphasize "install java11 on host: ${BK_APIGW_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -m "apigw" "mkdir ${INSTALL_PATH}/jvm/;tar -xf ${BK_PKG_SRC_PATH}/java11.tgz --strip-component=1 -C ${INSTALL_PATH}/jvm/"
        emphasize "install log_agent on host: ${BK_APIGW_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -m "apigw" "${CTRL_DIR}/bin/install_paas_plugins.sh -m apigw  --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/paas_plugins.env \
               -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    fi

    emphasize "install log_agent,log_parser on host: ${BK_PAAS_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "paas" "${CTRL_DIR}/bin/install_paas_plugins.sh -m paas --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/paas_plugins.env \
               -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    if ! [[ -z ${BK_APPT_IP_COMMA} ]]; then
        emphasize "install log_agent on host: ${BK_APPT_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -m "appt" "${CTRL_DIR}/bin/install_paas_plugins.sh -m appt -a appt --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/paas_plugins.env \
               -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    fi
    if ! [[ -z ${BK_APPO_IP_COMMA} ]]; then
        emphasize "install log_agent on host: ${BK_APPO_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -m "appo" "${CTRL_DIR}/bin/install_paas_plugins.sh -m appo -a appo --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/paas_plugins.env  -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    fi
    # 注册 app_code，消缺2024.2.7，app_code与数据库不一致导致监控告警发送失败，提示不匹配
    emphasize "add or update appcode: bk_paas_log_alert"
    add_or_update_appcode bk_paas_log_alert "$BK_PAAS_APP_SECRET"
}

install_nodeman () {
    local module=nodeman
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects["${module}"]}
    emphasize "grant rabbitmq private for ${module}"
    grant_rabbitmq_pri $module
    emphasize "install python on host: ${module}"
    install_python $module
    # 注册app_code
    emphasize "add or update appcode ${BK_NODEMAN_APP_CODE}"
    add_or_update_appcode "$BK_NODEMAN_APP_CODE" "$BK_NODEMAN_APP_SECRET"
    for project in ${projects[@]}; do
        local python_path=$(get_interpreter_path ${module} "${project}")
        for ip in "${BK_NODEMAN_IP[@]}"; do
            emphasize "install ${module} on host: ${ip}"
            cost_time_attention
            "${SELF_DIR}"/pcmd.sh -H "${ip}" \
                     "${CTRL_DIR}/bin/install_bknodeman.sh -e ${CTRL_DIR}/bin/04-final/bknodeman.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}  \
                                --python-path ${python_path} -b \$LAN_IP -w \"\$WAN_IP\""  || err "install ${module} ${project} failed on host: ${ip}" 
                     emphasize "register ${_project_consul[${target_name},${project}]} consul on host: ${ip}"
                     reg_consul_svc "${_project_consul[${target_name},${project}]}" "${_project_port[${target_name},${project}]}" "${ip}"
        done
    done

    # 注册权限模型
    emphasize "Registration authority model for ${module}"
    bkiam_migrate ${module}

    ## 更新加密工具
    encrytool=${CTRL_DIR}/support-files/tools/encrypted_tools/linux_$(uname -i)/encryptedpasswd
    encrytool_destdir="${INSTALL_PATH}/bknodeman/nodeman/script_tools/encrypted_tools/linux_$(uname -i)/"
    chmod +x $encrytool
    ## 兼容3.x平台部署
    if [[ $PLAT_VER < 4.0 ]]; then
        :
    else
        "${SELF_DIR}"/sync.sh "${module}" "${encrytool}" "${encrytool_destdir}"
        ## 兼容control机器部署nodeman的情况
        if [[ -d "${encrytool_destdir}" ]]; then
            /usr/bin/cp -rf "${encrytool}" "${encrytool_destdir}"
        fi
    fi

    ## consul 注册WAN_IP,WAN_IP先临时获取为LAN_IP
    consul kv put bkcfg/global/nodeman_wan_ip $LAN_IP

    # 安装openresty
    emphasize "install openresty on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"

    # openresty 服务器上安装consul-template
    emphasize "install consul template on host: ${module}"
    install_consul_template ${module} "${BK_NODEMAN_IP_COMMA}"

    # 启动
    "${SELF_DIR}"/pcmd.sh -m ${module} "systemctl start bk-nodeman.service"

    # nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "mount nfs to host: $BK_NFS_IP0"
        pcmdrc ${module} "_mount_shared_nfs bknodeman"
    fi

    if [[ -n $BK_AUTH_IP_COMMA ]]; then
        emphasize "sync open_paas data to bkauth"
        sync_secret_to_bkauth
    fi
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc ${module} "_sign_host_as_module consul-template"

}

install_gse () {
    _install_gse_project $@
}

_install_gse_project () {
    local module=gse
    local project=$1
    local gse_version=$(_get_version gse)
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    emphasize "add or update appcode: $BK_GSE_APP_CODE"
    add_or_update_appcode "$BK_GSE_APP_CODE" "$BK_GSE_APP_SECRET"
    emphasize "grant mongodb privilege for ${module}"
    grant_mongodb_pri ${module} 
    emphasize "init gse zk nodes on host: $BK_GSE_ZK_ADDR"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ZK_IP0}" "${CTRL_DIR}/bin/create_gse_zk_base_node.sh $BK_GSE_ZK_ADDR"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ZK_IP0}" "${CTRL_DIR}/bin/create_gse_zk_dataid_1001_node.sh"


    # 后续待定分模块部署细节 先全量
    # for project in ${_projects[${module}]};do
    #     emphasize "install ${module}-${project}"
    #     ${SELF_DIR}/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_gse.sh -e ${CTRL_DIR}/bin/04-final/gse.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}  -b \$LAN_IP"
    # done
    emphasize "install ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_gse.sh -e ${CTRL_DIR}/bin/04-final/gse.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}  -b \$LAN_IP -w \"\$WAN_IP\""
    for project in gse_task gse_api gse_procmgr gse_data gse_config; do
        reg_consul_svc ${_project_consul["${module},${project}"]} ${_project_port["${module},${project}"]} "${BK_GSE_IP_COMMA}"
    done

    # 启动
    "${SELF_DIR}"/pcmd.sh -m ${module} "systemctl start bk-gse.target"
    if [[ -n $BK_AUTH_IP_COMMA ]]; then
        emphasize "sync open_paas data to bkauth"
        sync_secret_to_bkauth
    fi
    ## gse 1.0不需要往apigw注册
    tmp_gv=$(echo $gse_version | grep -oP '(\d+.)' | tr -d "\n")
    if [[ $tmp_gv > 2.0 ]]; then
        emphasize "init apigateway data"
        "${SELF_DIR}"/pcmd.sh -H "$BK_APPO_IP0" "${CTRL_DIR}/bin/init_gse_apigw_data.sh  -c $BK_GSE_APP_CODE -s $BK_GSE_APP_SECRET -v $gse_version -l http://apigw-apigateway.service.consul:6006"
    fi
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_fta () {
    local module=fta
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    emphasize "install python on host: ${module}"
    install_python $module
    # 注册app_code
    emphasize "add or update appcode ${BK_FTA_APP_CODE}"
    add_or_update_appcode "$BK_FTA_APP_CODE" "$BK_FTA_APP_SECRET"
    # 初始化sql
    emphasize "migrate sql for fta"
    migrate_sql fta
    # 部署后台
    emphasize "install fta on host: ${BK_FTA_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m fta "${CTRL_DIR}/bin/install_fta.sh -b \$LAN_IP -e ${CTRL_DIR}/bin/04-final/fta.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH} -m fta"
    emphasize "register ${_project_consul["fta,fta"]}  consul on host: ${_project_ip["fta,fta"]}"
    reg_consul_svc "${_project_consul["fta,fta"]}" "${_project_port["fta,fta"]}" "${_project_ip["fta,fta"]}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_bklog () {
    local module=log
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    projects=${_projects[${module}]}

    emphasize "grant rabbitmq private for ${target_name}"
    grant_rabbitmq_pri $target_name

    # 初始化sql
    emphasize "migrate sql for ${module}"
    migrate_sql $module 
    emphasize "install python on host: ${module}"
    install_python $module
    # 注册app_code
    emphasize "add or update appocode ${BK_BKLOG_APP_CODE}"
    add_or_update_appcode "$BK_BKLOG_APP_CODE" "$BK_BKLOG_APP_SECRET"

    for project in ${projects[@]}; do
        local python_path=$(get_interpreter_path $module $project)
        IFS="," read -r -a target_server<<<${_project_ip["${target_name},${project}"]}
        for ip in ${target_server[@]}; do
            emphasize "install ${module} ${project} on host: ${ip}"
            cost_time_attention
            if [[ ${python_path} =~ "python" ]]; then
                "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bklog.sh  -m ${project} --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/bklog.env -b \$LAN_IP -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
            else
                "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bklog.sh  -m ${project} -e ${CTRL_DIR}/bin/04-final/bklog.env -b \$LAN_IP -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
            fi
            emphasize "register ${_project_consul[${target_name},${project}]}  consul on host: ${ip}"
            reg_consul_svc "${_project_consul[${target_name},${project}]}" "${_project_port[${target_name},${project}]}" "${ip}"
    	    emphasize "sign host as module"
    	    pcmdrc "${ip}" "_sign_host_as_module bk${module}-${project}"
        done
    done
    if [[ -n $BK_AUTH_IP_COMMA ]]; then
        emphasize "sync open_paas data to bkauth"
        sync_secret_to_bkauth
    fi
}

install_dbcheck () {
    [[ -f ${HOME}/.bkrc ]] && source $HOME/.bkrc
    if ! lsvirtualenv | grep deploy_check > /dev/null 2>&1; then
        emphasize "install dbcheck on host: 中控机"
        "${SELF_DIR}"/bin/install_py_venv_pkgs.sh -e -n deploy_check  \
        -p "/opt/py36/bin/python" \
        -w "${INSTALL_PATH}"/.envs -a "${SELF_DIR}/health_check" \
        -r "${SELF_DIR}/health_check/dbcheck_requirements.txt"
    else
        workon deploy_check && pip install -r "${SELF_DIR}/health_check/dbcheck_requirements.txt"
    fi
}

install_lesscode () {
    local module="lesscode"
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -P ${SELF_DIR}/bin/default/port.yaml -p ${BK_PKG_SRC_PATH}/${module}/project.yaml)
    # 注册app_code
    emphasize "add or update appcode ${BK_LESSCODE_APP_CODE}"
    add_or_update_appcode $BK_LESSCODE_APP_CODE $BK_LESSCODE_APP_SECRET
    # 初始化sql
    emphasize "migrate sql for ${module}"
    migrate_sql "${module}"
    # 安装lesscode
    emphasize "install lesscode on host: ${BK_LESSCODE_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${SELF_DIR}"/bin/install_lesscode.sh -e "${SELF_DIR}"/bin/04-final/lesscode.env \
                            -s "${BK_PKG_SRC_PATH}" -p "${INSTALL_PATH}" 
    emphasize "register ${_project_port["$module,$module"]}  consul server on host: ${BK_LESSCODE_IP_COMMA} "
    reg_consul_svc "${_project_consul["$module,$module"]}" "${_project_port["$module,$module"]}" ${BK_LESSCODE_IP_COMMA}
    # 写入hosts
    emphasize "add lesscode domain to hosts"
    pcmdrc lesscode "add_hosts_lesscode"
    # 注册工作台图标
    emphasize "register lesscode app icon"
    "${SELF_DIR}"/bin/bk-lesscode-reg-paas-app.sh

    # 安装openresty
    emphasize "install openresty on host: ${BK_NGINX_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -m nginx "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"

    emphasize "install consul template on host: ${BK_NGINX_IP_COMMA}"
    install_consul_template "lesscode" ${BK_NGINX_IP_COMMA} 

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc nginx "_sign_host_as_module consul-template"

    emphasize "set bk_lesscode as desktop display by default"
    set_console_desktop "bk_lesscode"
}

install_bkapi () {

    local module=bkapi_check
    emphasize "install consul-template on host: ${BK_APPO_IP_COMMA}"
    install_consul_template ${module} "${BK_NGINX_IP_COMMA}"

    emphasize "install python on hosts: ${BK_NGINX_IP_COMMA}"
    install_python nginx

    emphasize "install bkapi_check for nginx"
    cost_time_attention
    "${CTRL_DIR}"/pcmd.sh -m nginx "${CTRL_DIR}/bin/install_bkapi_check.sh -p ${INSTALL_PATH} -s ${BK_PKG_SRC_PATH} -m ${module}"

}

install_weopsconsul () {
    local module=weopsconsul
    emphasize "install init weopsconsul on host: ${BK_WEOPSCONSUL_INIT_IP}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_WEOPSCONSUL_INIT_IP}" "${CTRL_DIR}/bin/install_weops_consul.sh -i -k ${WEOPS_CONSUL_KEYSTR_32BYTES} -b ${BK_WEOPSCONSUL_INIT_IP}"
    emphasize "install weopsconsul on host: ${BK_WEOPSCONSUL_IP_COMMA}"
    for ip in ${BK_WEOPSCONSUL_IP[@]}; do
        if [[ $ip == ${BK_WEOPSCONSUL_INIT_IP} ]]; then
            emphasize "skip install weopsconsul on host: ${ip}"
            continue
        fi
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_weops_consul.sh" -b "${ip}" -k "${WEOPS_CONSUL_KEYSTR_32BYTES}" -j "${BK_WEOPSCONSUL_INIT_IP}"
    done
}

install_prometheus () {
    local module=prometheus
    # 如果没有prometheus master节点，退出并提示
    if [[ ${#BK_PROMETHEUS_MASTER_IP[@]} -eq 0 ]]; then
        err "prometheus 节点数为0,不支持"
    fi
    emphasize "install prometheus master on host: ${ip}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_PROMETHEUS_MASTER_IP}" "${CTRL_DIR}/bin/install_prometheus.sh" -a "${WEOPS_PROMETHEUS_PASSWORD}" -u '${WEOPS_PROMETHEUS_USER}' -s "${WEOPS_PROMETHEUS_SECRET_BASE64}" -b "${BK_PROMETHEUS_MASTER_IP}" -m true
    emphasize "install prometheus slave on host: ${BK_PROMETHEUS_SLAVE_IP}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_PROMETHEUS_SLAVE_IP}" "${CTRL_DIR}/bin/install_prometheus.sh" -a "${WEOPS_PROMETHEUS_PASSWORD}" -u '${WEOPS_PROMETHEUS_USER}' -s "${WEOPS_PROMETHEUS_SECRET_BASE64}" -b "${BK_PROMETHEUS_SLAVE_IP}" -m false
    for ip in ${BK_NGINX_IP[@]}; do
        emphasize "install prometheus nginx on host: ${ip}"
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_prometheus_nginx.sh -m ${BK_PROMETHEUS_MASTER_IP} -s ${BK_PROMETHEUS_SLAVE_IP}"
    done
}

install_echart () {
    local module=echarts
    emphasize "install echarts on host: ${BK_ECHARTS_IP_COMMA}"
    for ip in ${BK_ECHARTS_IP[@]}; do
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "docker rm -f echart || echo container echart does not exist ;docker run -d --restart=always --net=host --name=echart repo.service.consul:8181/ssr-echarts:latest"
        reg_consul_svc echart 3000 "${ip}"
    done
}

install_weops_vault () {
    local module=vault
    emphasize "create database for vault"
    mysql --login-path=mysql-default -e "CREATE DATABASE IF NOT EXISTS vault;"
    emphasize "grant mysql privilege for vault"
    ssh ${BK_MYSQL_MASTER_IP} "mysql --login-path=default-root -e \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'${BK_VAULT_INIT_IP}' IDENTIFIED BY '${BK_MYSQL_ADMIN_PASSWORD}';\""
    emphasize "install vault init node on host: ${BK_VAULT_INIT_IP}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_VAULT_INIT_IP}" "${CTRL_DIR}/bin/install_weops_vault.sh -i -s mysql-default.service.consul -p ${BK_MYSQL_ADMIN_PASSWORD} -P 3306 -u ${BK_MYSQL_ADMIN_USER}"
    reg_consul_svc vault 8200 "${BK_VAULT_INIT_IP}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_VAULT_INIT_IP}" "cat /data/vault.secret" > /data/vault.secret
    if [[ ! -f "${SELF_DIR}"/bin/04-final/vault.env ]]; then
        echo VAULT_UNSEAL_CODE=$(cat /data/vault.secret|grep 'Unseal Key'|awk '{print $4}') > "${SELF_DIR}"/bin/04-final/vault.env
        echo VAULT_ROOT_TOKEN=$(cat /data/vault.secret|grep 'Initial Root Token'|awk '{print $4}') >> "${SELF_DIR}"/bin/04-final/vault.env
        emphasize "vault unseal code: $(cat /data/vault.secret|grep 'Unseal Key'|awk '{print $4}')"
    else
        emphasize "vault already init, skip."
    fi
    emphasize "install vault on host: ${BK_VAULT_IP_COMMA}"
    for ip in ${BK_VAULT_IP[@]}; do
        if [[ $ip == ${BK_VAULT_INIT_IP} ]]; then
            emphasize "skip install vault on host: ${ip}"
            continue
        fi
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_weops_vault.sh -i false -s mysql-default.service.consul -p ${BK_MYSQL_ADMIN_PASSWORD} -P 3306 -u ${BK_MYSQL_ADMIN_USER}"
        reg_consul_svc vault 8200 "${ip}"
    done
}

install_automate () {
    local module=automate
    emphasize "install automate on host: ${BK_AUTOMATE_IP_COMMA}"
    for ip in ${BK_AUTOMATE_IP[@]}; do
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_automate.sh -b ${ip} -w http://prometheus.service.consul/api/v1/write -u ${WEOPS_PROMETHEUS_USER} -s ${WEOPS_PROMETHEUS_PASSWORD} -r redis.service.consul -P 6379 -a ${BK_REDIS_ADMIN_PASSWORD} -v http://vault.service.consul:8200 -t ${VAULT_ROOT_TOKEN}"
        reg_consul_svc automate 8089 "${ip}"
    done
}

install_weopsproxy () {
    local module=weopsproxy
    emphasize "install weopsproxy on host: ${BK_WEOPSPROXY_IP_COMMA}"
    for ip in ${BK_WEOPSPROXY_IP[@]}; do
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_weops_proxy.sh -r http://${WEOPS_PROMETHEUS_USER}:${WEOPS_PROMETHEUS_PASSWORD}@prometheus.service.consul/api/v1/write -c 127.0.0.1:8501" 
    done
}

install_weopsrdp () {
    local module=weopsrdp
    emphasize "install weopsrdp on host: ${BK_WEOPSRDP_IP_COMMA}"
    for ip in ${BK_WEOPSRDP_IP[@]}; do
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_weopsrdp.sh -s /o/ -I ${BK_PAAS_PUBLIC_URL}" 
    done
    emphasize "update consul kv"
    consul kv put bkapps/upstreams/prod/views "[\"${BK_WEOPSRDP_IP0}:8082\",\"${BK_WEOPSRDP_IP1}:8082 backup\"]"
    emphasize "reload nginx"
    "${SELF_DIR}"/pcmd.sh -m nginx 'systemctl reload consul-template && /usr/local/openresty/nginx/sbin/nginx -s reload'
}

install_minio () {
    local module=minio
    emphasize "install minio on host: ${BK_MINIO_IP_COMMA}"
    minio_server_list=""
    for ip in "${BK_MINIO_IP[@]}"; do
        minio_server_list+="http://$ip:9015/data "
    done
    minio_server_list=$(echo $minio_server_list | sed 's/ $//')
    for ip in ${BK_MINIO_IP[@]}; do
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_minio.sh -a ${WEOPS_MINIO_ACCESS_KEY} -s ${WEOPS_MINIO_SECRET_KEY} -l \"${minio_server_list}\""
        reg_consul_svc minio 9015 "${ip}"
    done
}

install_casbinmesh () {
    local module=casbinmesh
    emphasize "install casbinmesh init node on host: ${BK_CASBINMESH_INIT_IP}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_CASBINMESH_INIT_IP}" "${CTRL_DIR}/bin/install_casbin_mesh.sh -i -b ${BK_CASBINMESH_INIT_IP}"
    emphasize "install casbinmesh on host: ${BK_CASBINMESH_IP_COMMA}"
    for ip in ${BK_CASBINMESH_IP[@]}; do
        if [[ $ip == ${BK_CASBINMESH_INIT_IP} ]]; then
            emphasize "skip install casbinmesh on host: ${ip}"
            continue
        fi
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_casbin_mesh.sh -j ${BK_CASBINMESH_INIT_IP} -b ${ip}"
    done
}

install_trino () {
    local module=trino
    emphasize "install trino on host: ${BK_TRINO_IP_COMMA}"
    for ip in ${BK_TRINO_IP[@]}; do
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_trino.sh -m \"mongodb://${BK_MONGODB_ADMIN_USER}:${BK_MONGODB_ADMIN_PASSWORD}@mongodb.service.consul:27017/admin?replicaSet=rs0\" -e http://es7.service.consul:9200 -eu elastic -ep ${BK_ES7_ADMIN_PASSWORD} -my jdbc:mysql://mysql-default.service.consul:3306 -mu root -mp ${BK_MYSQL_ADMIN_PASSWORD} -i http://influxdb.service.consul:8086 -iu admin -ip ${BK_INFLUXDB_ADMIN_PASSWORD}"
        reg_consul_svc trino 8081 "${ip}"
    done
}

install_datart () {
    local module=datart
    emphasize "install datart init node on host: ${BK_DATART_INIT_IP}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_DATART_INIT_IP}" "${CTRL_DIR}/bin/install_datart.sh -m \"jdbc:mysql://mysql-default.service.consul:3306/datart?&allowMultiQueries=true&characterEncoding=utf-8\" -u root -p \"${BK_MYSQL_ADMIN_PASSWORD}\" -d ${BK_DOMAIN} -i"
    emphasize "install datart on host: ${BK_DATART_IP_COMMA}"
    for ip in ${BK_DATART_IP[@]}; do
        if [[ $ip == ${BK_DATART_INIT_IP} ]]; then
            emphasize "skip install datart on host: ${ip}"
            continue
        fi
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_datart.sh -m \"jdbc:mysql://mysql-default.service.consul:3306/datart?&allowMultiQueries=true&characterEncoding=utf-8\" -u root -p \"${BK_MYSQL_ADMIN_PASSWORD}\" -d ${BK_DOMAIN}"
        reg_consul_svc datart 8080 "${ip}"
    done
    emphasize "update consul kv"
    consul kv put bkapps/upstreams/prod/datart "[\"${BK_DATART_IP0}:8080\",\"${BK_DATART_IP1}:8080\"]"
    emphasize "sync static file to control"
    if [[ -f /data/static.tgz ]]; then
        emphasize "file already exists, skip"
    else
        rsync -avz $BK_DATART_INIT_IP:/tmp/static.tgz /data/
    fi
    emphasize "sync static file to paas"
    tar -xf /data/static.tgz -C /data/src/open_paas/paas/
    "${SELF_DIR}"/bkcli sync paas
    "${SELF_DIR}"/bkcli restart paas
}

install_weops_monstache () {
    local module=monstache
    emphasize "install monstache on host: ${BK_MONSTACHE_IP_COMMA}"
    for ip in ${BK_MONSTACHE_IP[@]}; do
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_monstache.sh -p \"${BK_CMDB_MONGODB_PASSWORD}\" -e \"${BK_ES7_ADMIN_PASSWORD}\""
    done
}

install_age () {
    local module=age
    emphasize "install age on host: ${BK_AGE_IP0}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_AGE_IP0}" "${CTRL_DIR}/bin/install_age.sh -u \"${WEOPS_AGE_DB_USER}\" -p \"${WEOPS_AGE_DB_PASSWORD}\" -d \"${WEOPS_AGE_DB_NAME}\""
    reg_consul_svc age 5432 "${BK_AGE_IP0}"
    emphasize "install age on host: ${BK_AGE_IP1}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_AGE_IP1}" "${CTRL_DIR}/bin/install_age.sh -u \"${WEOPS_AGE_DB_USER}\" -p \"${WEOPS_AGE_DB_PASSWORD}\" -d \"${WEOPS_AGE_DB_NAME}\""
}

install_kafkaadapter () {
    local module=kafkaadapter
    emphasize "install kafkaadapter on host: ${BK_KAFKAADAPTER_IP_COMMA}"
    APP_AUTH_TOKEN=$(mysql --login-path=mysql-default -eN "select auth_token from open_paas.paas_app where code='weops_saas';")
    if [[ -z ${APP_AUTH_TOKEN} ]]; then
        emphasize "get app auth token failed"
        exit 1
    else
        for ip in ${BK_KAFKAADAPTER_IP[@]}; do
            "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_kafka_adapter.sh -u \"${WEOPS_KAFKA_ADAPTER_USER}\" -p \"${WEOPS_KAFKA_ADAPTER_PASSWORD}\" -a \"${APP_AUTH_TOKEN}\""
        reg_consul_svc kafkaadapter 8080 "${ip}"
        done
    fi
}

install_vector () {
    local module=vector
    emphasize "install vector on host: ${BK_VECTOR_IP_COMMA}"
    for ip in ${BK_VECTOR_IP[@]}; do
        "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_vector.sh -u \"${WEOPS_PROMETHEUS_USER}\" -p \"${WEOPS_PROMETHEUS_PASSWORD}\" -w \"http://prometheus.service.consul/api/v1/write\""
    done
}

all_install_docker () {
    "${SELF_DIR}"/pcmd.sh -m all "${CTRL_DIR}/bin/install_docker_for_paasagent.sh"
}


module=${1:-null}
shift $(($# >= 1 ? 1 : 0))

case $module in
    paas|license|cmdb|job|gse|yum|consul|pypi|bkenv|rabbitmq|zk|mongodb|influxdb|license|cert|nginx|usermgr|appo|bklog|es7|python|appt|kafka|beanstalk|fta|dbcheck|controller|lesscode|node|bkapi|apigw|etcd|apisix|nfs)
        install_"${module}" $@
        ;;
    paas_plugins)
        install_paas_plugins
        ;;
    bkiam|iam)
        install_iam
        ;;
    bkauth|auth)
        install_auth
        ;;
    bkiam_search_engine|iam_search_engine)
        install_iam_search_engine
        ;;
    bknodeman|nodeman) 
        install_nodeman
        ;;
    bkmonitorv3|monitorv3)
        install_bkmonitorv3 "$@"
        ;;
    bkssm|ssm)
        install_ssm
        ;;
    saas-o) 
        install_saas-o "$@"
        ;;
    saas-t)
        install_saas-t "$@"
        ;;
    mysql|redis_sentinel|redis)
        install_"${module}"_common "$@"
        ;;
    weopsconsul)
        install_weopsconsul "$@"
        ;;
    prometheus)
        install_prometheus "$@"
        ;;
    echart)
        install_echart "$@"
        ;;
    vault)
        install_weops_vault "$@"
        ;;
    automate)
        install_automate "$@"
        ;;
    weopsproxy)
        install_weopsproxy "$@"
        ;;
    weopsrdp)
        install_weopsrdp "$@"
        ;;
    minio)
        install_minio "$@"
        ;;
    casbinmesh)
        install_casbinmesh "$@"
        ;;
    trino)
        install_trino "$@"
        ;;
    datart)
        install_datart "$@"
        ;;
    monstache)
        install_monstache "$@"
        ;;
    age)
        install_age "$@"
        ;;
    kafkaadapter)
        install_kafkaadapter "$@"
        ;;
    vector)
        install_vector "$@"
        ;;
    docker)
        all_install_docker "$@"
        ;;
    null) # 特殊逻辑，兼容source脚本
        ;;
    *)
        echo "$module 不支持"
        exit 1
        ;;
esac