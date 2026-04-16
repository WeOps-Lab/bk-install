#!/bin/bash
# Script Name: weops_settings_custom.sh
# Description: Script to configure weops custom settings after deployment saas
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

source /data/install/utils.fc
SELF_DIR=$(readlink -f "$(dirname "$0")")

# 修改告警事件自动关闭时间
/data/install/pcmd.sh -H $BK_MYSQL_IP0 "mkdir -p ${SELF_DIR}/../sqlfile"
scp ${SELF_DIR}/../sqlfile/*.sql $BK_MYSQL_IP0:${SELF_DIR}/../sqlfile/
scp ${SELF_DIR}/../sqlfile/*.gz $BK_MYSQL_IP0:${SELF_DIR}/../sqlfile/
/data/install/pcmd.sh -H $BK_MYSQL_IP0 "mysql --login-path=default-root < ${SELF_DIR}/../sqlfile/cw_uac_saas.sql"

# 导入ITSM SQL数据
itsm_version=$(docker exec mysql-client mysql -h $BK_MYSQL_IP -uroot -p$BK_MYSQL_ADMIN_PASSWORD -N -s -e "use open_paas;SELECT v.version FROM paas_saas_app_version v INNER JOIN paas_saas_app a ON a.current_version_id = v.id WHERE a.code = 'bk_itsm';")
if echo $itsm_version | grep "4.29" >/dev/null; then
  echo "ITSM version is 4.29, need to import SQL data"
  cat /data/src/patch/sql/weops_itsm_table.*.sql | docker exec -i mysql-client mysql -h $BK_MYSQL_IP -uroot -p$BK_MYSQL_ADMIN_PASSWORD -Dbk_itsm
else
  echo "ITSM version is not 4.29, need to import SQL data"
  /data/install/pcmd.sh -H $BK_MYSQL_IP0 "gunzip -c ${SELF_DIR}/../sqlfile/weops_itsm_table.20240424.sql.gz | docker exec -i mysql mysql -h $BK_MYSQL_IP -uroot -p$BK_MYSQL_ADMIN_PASSWORD -Dbk_itsm"
fi
# 生成登陆密码加密需要的环境变量
python <<EOF
import base64
from Cryptodome.PublicKey import RSA
c = RSA.generate(1024)
public_key = base64.b64encode(c.publickey().exportKey()).decode()
private_key = base64.b64encode(c.exportKey("PEM")).decode()
with open("/data/install/bin/03-userdef/paas.env", "a") as f:
    f.write("\n")
    f.write(f"BK_ENABLE_PASSWORD_RSA_ENCRYPTED=true\n")
    f.write(f"BK_PASSWORD_RSA_PUBLIC_KEY='{public_key}'\n")
    f.write(f"BK_PASSWORD_RSA_PRIVATE_KEY='{private_key}'\n")
    f.write("\n")
EOF

# # 重新下发环境变量，渲染配置文件，重启服务

/data/install/bkcli install bkenv
/data/install/bkcli sync common
/data/install/bkcli sync paas
/data/install/bkcli render paas
/data/install/bkcli restart paas login


# 优化用户登陆锁定显示
sed -i '174s/PASSWORD_ERROR/TOO_MANY_TRY/' /data/src/usermgr/api/bkuser_core/api/login/views.py
/data/install/bkcli sync usermgr
/data/install/bkcli install usermgr
/data/install/bkcli restart usermgr



# 替换paas.conf模板(屏蔽后台+nginx上传上限)
sed -i "s/xxx.xxx/$BK_DOMAIN/g" ${SELF_DIR}/../template/paas.conf
/data/install/pcmd.sh -m nginx "mv /etc/consul-template/templates/paas.conf /etc/consul-template/templates/paas.conf.bak"
scp ${SELF_DIR}/../template/paas.conf $BK_NGINX_IP:/etc/consul-template/templates/
/data/install/pcmd.sh -m nginx "chmod 755 /etc/consul-template/templates/paas.conf"
/data/install/bkcli restart nginx


# 渲染itsm访问入口
consul kv put bkcfg/weops/weops_itsm_domain "itsm.${BK_DOMAIN}"
/data/install/pcmd.sh -m nginx "docker restart consul-template"
/data/install/pcmd.sh -m nginx "docker exec nginx /usr/local/openresty/nginx/sbin/nginx -s reload"
