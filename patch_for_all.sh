#!/bin/bash


CTRL_DIR=/data/install
PATCH_DIR=/data/src/patch
sh_base_dir=$( dirname $(readlink -f $0) )
gomysql='docker exec mysql-client mysql --login-path=default-root --socket=/var/run/mysql/default.mysql.socket'
gomysqldump='docker exec mysql-client mysqldump --login-path=default-root --socket=/var/run/mysql/default.mysql.socket'


green () {
    echo -e "\033[32m$1\033[0m"
}


red () {
    echo -e "\033[31m$1\033[0m"
}


blue () {
    echo -e "\033[34m$1\033[0m"
}


#---------- 开启全文索引所需动作 ----------
cmdb_full_text () {
sed -i 's/fullTextSearch: "off"/fullTextSearch: "on"/' /data/src/cmdb/support-files/templates/server#conf#common.yaml

source ~/.bkrc && source $CTRL_DIR/utils.fc
cat << EOF >> /data/install/bin/03-userdef/cmdb.env
BK_CMDB_ES7_PASSWORD=${BK_ES7_ADMIN_PASSWORD}
BK_CMDB_ES7_REST_ADDR=es7.service.consul:9200
EOF

for index in cmdb.cc_applicationbase cmdb.cc_objdes cmdb.cc_hostbase cmdb.cc_objectbase bk_cmdb.bk_biz_set_obj;do
    curl -sSL -XPUT -u elastic:$BK_ES7_ADMIN_PASSWORD http://es7.service.consul:9200/$index|jq;
done > /dev/null

# 修改es最大查询数量，修复cmdb全文检索内容较少时报错
ELASTICSEARCH_URL="es7.service.consul:9200"
USERNAME="elastic"
PASSWORD="${BK_ES7_ADMIN_PASSWORD}"
NEW_SETTING='{
  "index": {
    "max_result_window": 10000
  }
}'
indices=$(curl -s -u "$USERNAME:$PASSWORD" "$ELASTICSEARCH_URL/_cat/indices?h=index")
for index in $indices; do
  if [[ $index == bk_cmdb* ]]; then
    echo "Updating settings for index: $index"
    curl -X PUT "$ELASTICSEARCH_URL/$index/_settings" -u "$USERNAME:$PASSWORD" -H 'Content-Type: application/json' -d "$NEW_SETTING"
  fi
done

cd $CTRL_DIR
./bkcli install bkenv
./bkcli sync common
./bkcli initdata cmdb
if [[ $(dig consul.service.consul +short | wc -l) -lt 3 ]];then
    ./bkcli sync cmdb
    ./bkcli render cmdb
    ./bkcli install cmdb
else
    ./pcmd.sh -m cmdb 'cp -a /data/bkce/cmdb/server/conf/redis.yaml /tmp/'
    ./bkcli sync cmdb
    ./bkcli render cmdb
    ./bkcli install cmdb
    ./pcmd.sh -m cmdb 'rm -f /data/bkce/cmdb/server/conf/redis.yaml && mv /tmp/redis.yaml /data/bkce/cmdb/server/conf/'
fi
./bkcli restart cmdb
}

#---------- 4.14 bk_login ----------
change_bk_login () {
mkdir -p /tmp/bk_login
tar xf ${PATCH_DIR}/yum/bk_login.*gz -C /tmp/bk_login
source ~/.bkrc && source $CTRL_DIR/utils.fc
for i in $( tr -s ',' ' ' <<< $BK_PAAS_IP_COMMA);do
    scp -r /tmp/bk_login $i:/tmp/ > /dev/null
done
cd $CTRL_DIR
./pcmd.sh -m paas "cp -ar /data/bkce/open_paas/login{,_$(date +%F)_bak}"
./pcmd.sh -m paas "rsync -avP /tmp/bk_login/ /data/bkce/open_paas/login/"
cat << 'EOF' >> bin/03-userdef/paas.env
BK_ENABLE_PASSWORD_RSA_ENCRYPTED=true
BK_PASSWORD_RSA_PUBLIC_KEY='LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlHZk1BMEdDU3FHU0liM0RRRUJBUVVBQTRHTkFEQ0JpUUtCZ1FDb1hVSU92UzRCWU9uRlRiNS91SW0vTzYvUApLU3VaRWtJVEhzakI5bE1hUDk4TXFMSWxjV2k1ZUhRZUdrSkZhbjBUdVp1NXJzTlZoNU52Yzhnb1piRWU3WndtCnRCYXliNGZGdjYzTC9yT2VhYkFiQTdNa2hwNmZIZE5KNjFaRTBuZ2kyQ2lCTFk3R2U0Q2h4NHhmSkcyczhjc1gKTFpKTXZFTkcrQ2VGSmJPeDRRSURBUUFCCi0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQ=='
BK_PASSWORD_RSA_PRIVATE_KEY='LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlDV3dJQkFBS0JnUUNvWFVJT3ZTNEJZT25GVGI1L3VJbS9PNi9QS1N1WkVrSVRIc2pCOWxNYVA5OE1xTElsCmNXaTVlSFFlR2tKRmFuMFR1WnU1cnNOVmg1TnZjOGdvWmJFZTdad210QmF5YjRmRnY2M0wvck9lYWJBYkE3TWsKaHA2ZkhkTko2MVpFMG5naTJDaUJMWTdHZTRDaHg0eGZKRzJzOGNzWExaSk12RU5HK0NlRkpiT3g0UUlEQVFBQgpBb0dBRndRQXBzRW55OXB5dXAwaElKYWFoZ0Rqekw4RkRiellPWUxvME5NYWt5a09GYzN0NUg1M1lYdGM3RXlNCnFLNmhBSlJML0hzdWlyK280UUNENlRuVmwzcklHRTFXRXR6SVU1L1VqSUhOa3R1REdtMGF6VTZaL0VHa05vbnYKaXF3OGNpWDRTN05TWUg5L0R0YkR1a0tKaCtUQ2pIenYxS2JTZ2xOdEoxWng0VzBDUVFDOXZkVVVIOFBmWGM4Swo4MWJYbm02clNSWDVUZmlNbmRTandtaERKazFyVHU1L25VK1Z6bTB3V1NjbDNJRHZoc25GbmlpL0tRd2M3KzZYClhNUHY0a0dEQWtFQTR5aGh3ZGZrNkxZVS9aYXpmZy9FVzU3L3h1VTdRS0dWbUlxcFRiZkRvZEk5cllwZjNiTW4KQ05FUFQzWXMxaUE1YmxkNHplWCtEYTBZQjZkeGVFNFZ5d0pBYmFCRmdUZ05LbnYveUxycG5QQ2J6bmtPcWhrRApsdk1Gell2Z1E1UFl2VHhBamhqc3g0Z2FEQW9tbFRoK2dtWGxKRG1LSDFCdkFEVWNLL1hiK3poRlV3SkFEVFdVCjhiTy9RUFVOcFcxMUJKaWdIMy9RZWQxc282YUJ6M3dJdWxjOFRoV3V0bis4Y1dUd21TZW5EMFRjK0pxcEhFeUQKM3QxSDk3MmdEeG5pbEU5ZUh3SkFSSC9kdVRwVkFNVGRnNkVzRmszRm02dWxaMU5PNkR0ZDdMVVpxYVNTa1BVOAoyWldpSVQ5eFNCanpOQjdnanhJOTRrNWs4aXF0UGllTHNXS0R3eEsweFE9PQotLS0tLUVORCBSU0EgUFJJVkFURSBLRVktLS0tLQ=='
EOF
./bkcli install bkenv
./bkcli sync common
./bkcli render paas
./pcmd.sh -m paas "chown -R blueking. /data/bkce/open_paas/login;docker restart bk-paas-login;"
}

#--------- 替换 starter ----------
change_starter () {
source ~/.bkrc && source $CTRL_DIR/utils.fc
for i in $( tr -s ',' ' ' <<< $BK_APPO_IP_COMMA);do
    scp ${PATCH_DIR}/yum/starter $i:/data/bkce/paas_agent/paas_agent/etc/build/docker/saas/
done
cd $CTRL_DIR
./pcmd.sh -m appo "cd /data/bkce/paas_agent/paas_agent/etc/build/docker/saas/;chmod a+x starter;chown blueking. starter;systemctl restart bk-paasagent"
}

init_for_lib64 () {
local ips=($(grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' /data/install/install.config | sort -u))
local os_family="${2:-no}"
local lib_path="${3:-no}"

if [[ $lib_path == "no" ]];then
    lib_path=$(ldd "$(which ssh)" | awk '{print $3}' | grep '^/' | head -n 1 | xargs dirname)
fi

case "$os_family" in
    rhel)
        for ip in ${ips[@]};do
            scp ${PATCH_DIR}/yum/libcrypto.so.1.0.2k $ip:/lib64/
            scp ${PATCH_DIR}/yum/libssl.so.1.0.2k $ip:/lib64/
            ssh $ip "ln -s /lib64/libssl.so.1.0.2k /lib64/libssl.so.10 2>/dev/null"
            ssh $ip "ln -s /lib64/libcrypto.so.1.0.2k /lib64/libcrypto.so.10 2>/dev/null"
            ssh $ip "ls -l /lib64/libssl.so.10"
            ssh $ip "ls -l /lib64/libcrypto.so.10"
            ssh $ip "yum -y install langpacks-en glibc-all-langpacks"
            ssh $ip "dnf -y module disable mysql redis"
        done

        rsync -avP ${PATCH_DIR}/yum/rpms/ /opt/yum/
        rsync -avP ${PATCH_DIR}/yum/image/ /data/src/image/

        mkdir /data/install/support-files/dockerfiles
        for i in $( cat ${PATCH_DIR}/yum/txt );do
            rsync -avP ${PATCH_DIR}/yum/install/$i /data/install/$i
        done

        cd $CTRL_DIR
        sed -i 's/sysvinit-tools//g' bin/update_bk_env.sh bin/install_controller.sh
        # yum -q -y install ${PATCH_DIR}/yum/pssh-2.3.1-29.el8.noarch.rpm
        yum -q -y install /opt/yum/parallel-20160222-1.el7.noarch.rpm
        ;;
    kylin)   
        for ip in ${ips[@]};do
            ssh $ip "cp /data/initsvr/libssl.so.10 /usr/lib64/"
            ssh $ip "cp /data/initsvr/libcrypto.so.10 /usr/lib64/"
            ssh $ip "cp /data/initsvr/libpython3.6m.so.1.0 /usr/lib64/"
            ssh $ip "chmod 755 /usr/lib64/libssl.so.10 /usr/lib64/libcrypto.so.10 /usr/lib64/libpython3.6m.so.1.0"
        done
        cd $CTRL_DIR
        sed -i 's/sysvinit-tools//g' bin/update_bk_env.sh bin/install_controller.sh
        ./bkcli sync common
        ;;
    euler)
        for ip in ${ips[@]};do
            ssh $ip "cp -f ${PATCH_DIR}/yum/libcrypto.so.1.0.2k /usr/lib64/"
            ssh $ip "cp -f ${PATCH_DIR}/yum/libssl.so.1.0.2k /usr/lib64/"
            ssh $ip "chmod 755 /usr/lib64/libcrypto.so.1.0.2k /usr/lib64/libssl.so.1.0.2k"
            ssh $ip "ln -s /usr/lib64/libcrypto.so.1.0.2k  /usr/lib64/libcrypto.so.10 && ln -s /usr/lib64/libcrypto.so.1.0.2k  /usr/lib64/libcrypto.so"
            ssh $ip "ln -s /usr/lib64/libssl.so.1.0.2k  /usr/lib64/libssl.so.10 && ln -s /usr/lib64/libssl.so.1.0.2k  /usr/lib64/libssl.so"
        done 
        cd $CTRL_DIR
        sed -i 's/sysvinit-tools//g' bin/update_bk_env.sh bin/install_controller.sh
        cp -f ${PATCH_DIR}/yum/RPM-GPG-KEY-EPEL-7 /etc/pki/rpm-gpg/
        cp -f ${PATCH_DIR}/yum/epel.repo /etc/yum.repos.d/
        cp -f ${PATCH_DIR}/yum/openeuler.repo /etc/yum.repos.d/
        yum -y -q install ${PATCH_DIR}/yum/pssh-2.3.1-5.el7.noarch.rpm
        yum -y -q install /opt/yum/parallel*
        ;;
    ubuntu)
        for ip in ${ips[@]};do
            ssh $ip "cp -f ${PATCH_DIR}/yum/libcrypto.so.1.0.2k /lib/x86_64-linux-gnu/"
            ssh $ip "cp -f ${PATCH_DIR}/yum/libssl.so.1.0.2k /lib/x86_64-linux-gnu/"
            ssh $ip "chmod 755 /lib/x86_64-linux-gnu/libcrypto.so.1.0.2k /lib/x86_64-linux-gnu/libssl.so.1.0.2k"
            ssh $ip "ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.2k  /lib/x86_64-linux-gnu/libcrypto.so.10 && ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.2k  /lib/x86_64-linux-gnu/libcrypto.so"
            ssh $ip "ln -s /lib/x86_64-linux-gnu/libssl.so.1.0.2k  /lib/x86_64-linux-gnu/libssl.so.10 && ln -s /lib/x86_64-linux-gnu/libssl.so.1.0.2k  /lib/x86_64-linux-gnu/libssl.so"
        done 
        ;;
    define)
        if [[ ! -d $lib_path ]];then
            echo "lib_path $lib_path not exist"
            exit 1
        else
            for ip in ${ips[@]};do
                scp ${PATCH_DIR}/yum/libcrypto.so.1.0.2k $ip:$lib_path/
                scp ${PATCH_DIR}/yum/libssl.so.1.0.2k $ip:$lib_path/
                ssh $ip "chmod 755 $lib_path/libcrypto.so.1.0.2k $lib_path/libssl.so.1.0.2k"
                ssh $ip "ln -s $lib_path/libssl.so.1.0.2k $lib_path/libssl.so.10 2>/dev/null"
                ssh $ip "ln -s $lib_path/libcrypto.so.1.0.2k $lib_path/libcrypto.so.10 2>/dev/null"
                ssh $ip "ls -l $lib_path/libssl.so.10"
                ssh $ip "ls -l $lib_path/libcrypto.so.10"
            done
        fi
        ;;
    *)
    echo "ERROR: unsupported os_family '$os_family' (use: debian|rhel)" >&2
    return 1
    ;;
esac
}

init_platform () {
local os_family="${2:-no}"

case "$os_family" in
    rhel)
        source ~/.bkrc && source $CTRL_DIR/utils.fc
        cd $CTRL_DIR
        sed -i 's/innodb_file_format/# innodb_file_format/g' bin/install_mysql.sh
        sed -i 's/query_cache_size/# query_cache_size/g' bin/install_mysql.sh
        sed -i 's/query_cache_type/# query_cache_type/g' bin/install_mysql.sh
        sed -i 's/show_compatibility_56/# show_compatibility_56/g' bin/install_mysql.sh
        sed -i '29,35s/^/# /' /data/src/open_paas/projects.yaml
        sed -i '23,29s/^/# /' /data/src/bkmonitorv3/projects.yaml
        sed -i 's/set_console_desktop/# set_console_desktop/g' install.sh
        ./pcmd.sh -m all "yum -y remove podman runc"
        ./pcmd.sh -m all "[[ ! -f /etc/resolv.conf ]] && touch /etc/resolv.conf"
        cp -f $sh_base_dir/yum/bk_sops-3.6.56.x.tar.gz /data/src/official_saas/
        bash bin/install_docker_for_paasagent.sh
        ./bkcli sync common
        ;;
    kylin)
        source ~/.bkrc && source $CTRL_DIR/utils.fc
        cd $CTRL_DIR
        ./sync.sh all /usr/lib64/libssl.so.10 /usr/lib64/
        ./sync.sh all /usr/lib64/libcrypto.so.10 /usr/lib64/
        ./sync.sh all /usr/lib64/libpython3.6m.so.1.0 /usr/lib64/
        ./pcmd.sh -m all "yum makecache"
        ./pcmd.sh -m all "yum -y remove jq*"
        ./pcmd.sh -m all "yum -y install jq-1.6*"
        sed -i '/# 安装 mongodb/,/fi/ s/^/# /' bin/install_mongodb.sh
        sed -i '/安装 mongodb/i yum -y install mongodb-4.2.3 || error "安装mongodb失败"' bin/install_mongodb.sh
        sed -i '/systemctl enable --now influxdb/i cp /usr/lib/influxdb/scripts/influxdb.service /usr/lib/systemd/system/' bin/install_influxdb.sh
        cp -f $sh_base_dir/yum/mongodb-4.2.3-1.ky10.x86_64.rpm /opt/yum/
        cp -f $sh_base_dir/yum/bk_sops-3.6.56.x.tar.gz /data/src/official_saas/
        for i in $( tr -s ',' ' ' <<< $BK_APPO_IP_COMMA);do
            ssh $i "sed -i '/yum install -y \$YUM_LIST/s/^/#/' /data/bkce/paas_agent/paas_agent/etc/build/docker/saas/builder"
            ssh $i "sed -i '/chown/s/$/ \/cache/g'/data/bkce/paas_agent/paas_agent/etc/build/docker/saas/builder"
        done
        createrepo /opt/yum/
        ./pcmd.sh -m all "yum clean all && yum makecache"
        ./bkcli sync common
        ./pcmd.sh -m all "yum -y install $CTRL_DIR/yum/fuse3-libs-3.3.0-18.el8.x86_64.rpm $CTRL_DIR/yum/fuse-overlayfs-0.7.8-1.x86_64.rpm $CTRL_DIR/yum/slirp4netns-0.4.2-3.x86_64.rpm"
        ;;
    *)
        echo "ERROR: unsupported os_family '$os_family' (use: debian|rhel)" >&2
        return 1
        ;;
esac
}

# ---------- change static for report ----------
change_static () {
source ~/.bkrc && source $CTRL_DIR/utils.fc
for i in $( tr -s ',' ' ' <<< $BK_PAAS_IP_COMMA);do
    ssh $i "tar xf ${PATCH_DIR}/yum/static.tgz -C /data/bkce/open_paas/paas/"
done
cd $CTRL_DIR
./bkcli restart paas paas
}

# ---------- close bkmonitorv3 ENABLE_DEFAULT_STRATEGY ----------
close_default_strategy () {
source ~/.bkrc && source $CTRL_DIR/utils.fc
ssh mysql-default.service.consul "$gomysql -e 'UPDATE bkmonitorv3_alert.global_setting SET \`value\`=0 WHERE \`key\`=\"ENABLE_DEFAULT_STRATEGY\";'"
}

# ---------- change bkmonitorv3 default strategy notification channel ----------
change_default_noti () {
source ~/.bkrc && source $CTRL_DIR/utils.fc
ssh mysql-default.service.consul "$gomysqldump bkmonitorv3_alert user_group > /tmp/user_group.sql"
json_data='[{\"time_range\": \"00:00:00--23:59:00\", \"notify_config\": [{\"type\": [\"voice\"], \"level\": 3}, {\"type\": [\"voice\"], \"level\": 2}, {\"type\": [\"voice\"], \"level\": 1}]}]'
ssh mysql-default.service.consul "$gomysql -e \"update bkmonitorv3_alert.user_group set alert_notice='${json_data}';\""
}

# ---------- patch for ha ----------
patch_for_ha () {
cd /data/weops/install
sed -i 's/data\/bkce\/bkcli/data\/install\/bkcli/g' ./weops_settings_custom.sh
sed -i '/weops\/bk_login/a scp /data/weops/bk_login.*.tar.gz $BK_PAAS_IP1:/tmp' ./weops_settings_custom.sh
sed -i 's/ssh $BK_MYSQL_IP/ssh mysql-default.service.consul/g' ./install_saas.sh
sed -i 's/$BK_MYSQL_IP/mysql-default.service.consul/g' ./install_saas.sh ./weops_settings_logs.sh ./weops_settings_custom.sh
sed -i 's/$BK_MYSQL_IP0/mysql-default.service.consul/g' ./weops_settings_custom.sh

# ----- 修改变量部分 -----
vars_dir='/data/weops/install/canway_saas_vars.txt'
source ~/.bkrc && source /data/install/utils.fc
cw_uac_saas_vars="CHART_URL=http:\/\/echart.service.consul:3000\/ \
ELASTICSEARCH_HOST=es7.service.consul \
REDIS_MODE=SENTINEL \
KAFKA_HOST=kafka.service.consul \
REDIS_HOST=redis-sentinel.service.consul \
REDIS_PORT=26379"
bk_itsm_vars="ES_HOST=es7.service.consul"
weops_saas_vars="REDIS_HOST=$BK_REDIS_IP \
AUTO_MATE_URL=http:\/\/automate.service.consul:8089 \
BKIAM_DB_HOST=mysql-default.service.consul \
GH_MINIO_ENDPOINT=minio.service.consul:9015 \
METRICS_URL=http:\/\/admin:admin@prometheus.service.consul\/api\/v1\/query \
TRINO_HOST=trino.service.consul \
TRINO_PORT=8081 \
VAULT_URL=http:\/\/vault.service.consul:8200 \
WEOPS_PROXY_CLIENT_HOST=127.0.0.1 \
GH_MINIO_EXTERNAL_ENDPOINT_USE_HTTPS=False"
change_vars () {
    for i in $2;do
        key=$(awk -F= '{print $1}' <<< $i)
        value="$(awk -F= '{print $2}' <<< $i)"
        if ! grep ${1}: $vars_dir | grep -q $key;then
            sed -i "/${1}:/s/$/;BKAPP_$key=$value/" $vars_dir
        else
            sed -i "/${1}:/s/BKAPP_$key=[^;]*/BKAPP_$key=$value/" $vars_dir
        fi
    done
}
change_vars cw_uac_saas "$cw_uac_saas_vars"
change_vars bk_itsm "$bk_itsm_vars"
change_vars weops_saas "$weops_saas_vars"

# ----- 新增 APP_CODE 的部分 -----
bk_sops_vars="bk_sops:REDIS_HOST=redis-sentinel.service.consul;\
REDIS_MODE=sentinel;\
REDIS_PORT=26379"
add_vars () {
    if ! grep -q ${1}: $vars_dir;then
        echo $2 >> $vars_dir
    fi
}
add_vars bk_sops $bk_sops_vars
}

# 分发文件
/data/install/sync.sh all /data/src/patch /data/src/

case $1 in
    change_starter)
        change_starter
        ;;
    change_bk_login)
        change_bk_login
        ;;
    change_static)
        change_static
        ;;
    cmdb_full_text)
        cmdb_full_text
        ;;
    init_for_lib64)
        init_for_lib64 $@
        ;;
    init_platform)
        init_platform $@
        ;;
    ha)
        patch_for_ha
        ;;
    close_default_strategy)
        close_default_strategy
        ;;
    change_default_noti)
        change_default_noti
        ;;
    all)
        change_bk_login
        cmdb_full_text
        change_static
        close_default_strategy
        change_default_noti
        ;;
    *)
        red "未识别的参数." && exit 0
        ;;
esac
