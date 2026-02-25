#!/usr/bin/env bash
# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -my --mysql-url         [必填] "mysql的url" ]
            [ -mu --mysql-username     [必填] "mysql的用户名" ]
            [ -mp --mysql-password     [必填] "mysql的密码" ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "$@"
}

error () {
    echo "$@" 1>&2
    usage_and_exit 1
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "$PROGRAM version $VERSION"
}

(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --mysql-url | -my)  
            shift
            MYSQL_URL=$1
            ;;
        --mysql-username | -mu)
            shift
            MYSQL_USERNAME=$1
            ;;
        --mysql-password | -mp) 
            shift
            MYSQL_PASSWORD=$1
            ;;
        --datart_url | -du)
            shift
            DATART_URL=$1
            ;;
        -*)
            error "不可识别的参数: $1"
            ;;
        *) 
            break
            ;;
    esac
    shift 
done 

# 检查必填参数
if [[ -z $MYSQL_URL ]]; then
    error "缺少必填参数: --mysql-url"
fi

if [[ -z $MYSQL_USERNAME ]]; then
    error "缺少必填参数: --mysql-username"
fi

if [[ -z $MYSQL_PASSWORD ]]; then
    error "缺少必填参数: --mysql-password"
fi


# source /data/install/utils.fc
 
curl -s "${DATART_URL}/api/v1/users/login" -i \
-H 'Content-Type: application/json' \
-d '{"username":"admin","password":"WeOps2023"}' \
--compressed \
--insecure > /tmp/datart.login

if ! grep -q Authorization /tmp/datart.login; then
    log "/tmp/datart.login内容如下:"
    cat /tmp/datart.login
    error "登录datart失败，请检查datart服务是否正常，或者登录信息是否正确"
fi

export AUTH=$(grep Authorization /tmp/datart.login)
 
cat << EOF > /tmp/payload.json
{
    "config": {
        "dbType": "MYSQL",
        "url": "jdbc:mysql://${MYSQL_URL}",
        "user": "${MYSQL_USERNAME}",
        "password": "${MYSQL_PASSWORD}",
        "driverClass": "com.mysql.cj.jdbc.Driver",
        "serverAggregate": false,
        "enableSpecialSQL": false,
        "enableSyncSchemas": true,
        "syncInterval": "60",
        "properties": {}
    },
    "createTime": "2023-05-30 17:33:24",
    "id": "e866c2e14c0b4aaf956110a63f7d5ba6",
    "index": null,
    "isFolder": false,
    "name": "mysql",
    "orgId": "b044363c75a34df8b40e26c1a61e5dde",
    "parentId": null,
    "permission": null,
    "schemaUpdateDate": "2023-06-05 10:42:16",
    "status": 1,
    "type": "JDBC",
    "updateBy": "1e7f1b3aac2247008e5e0e9be07da599",
    "updateTime": "2023-05-30 17:42:01",
    "deleteLoading": false
}
EOF

RESP=$(curl -s "${DATART_URL}/api/v1/sources/e866c2e14c0b4aaf956110a63f7d5ba6" \
-X 'PUT' \
-H "${AUTH}" \
-H 'Content-Type: application/json' \
--data-binary @/tmp/payload.json \
--compressed \
--insecure)

SUCCESS=$(echo "$RESP" | jq -r '.success')
if [[ "$SUCCESS" != "true" ]]; then
    log "更新数据源失败，响应内容如下:"
    echo "$RESP"
    error "更新数据源失败，请检查datart服务是否正常，或者登录信息是否正确"
else
    log "更新数据源成功"
    rm -vf /tmp/payload.json /tmp/datart.login
fi
