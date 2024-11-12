#!/usr/bin/env bash
# 通用脚本框架变量
set -euo pipefail
PROGRAM=$(basename "$0")
EXITCODE=0

source /data/install/weops_version
# IMAGE="docker-bkrepo.cwoa.net/ce1b09/weops-docker/datart:latest"

VERSION="1.0.0"
PORT=8081
INIT=false

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -m --mysql-url          [必填] "mysql的连接地址" ]
            [ -p --mysql-password     [必填] "mysql的密码" ]
            [ -u --mysql-username     [必填] "mysql的用户名" ]
            [ -d --domain             [必填] "域名" ]
            [ -i --init               [必填] "初始化" ]
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
        --mysql-url | -m)
            shift
            MYSQL_URL=$1
            ;;
        --mysql-username | -u)
            shift
            MYSQL_USERNAME=$1
            ;;
        --mysql-password | -p)
            shift
            MYSQL_PASSWORD=$1
            ;;
        --domain | -d)
            shift
            DOMAIN=$1
            ;;
        --init | -i)
            INIT=true
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
    error "mysql的连接地址不能为空"
fi

if [[ -z $MYSQL_USERNAME ]]; then
    error "mysql的用户名不能为空"
fi

if [[ -z $MYSQL_PASSWORD ]]; then
    error "mysql的密码不能为空"
fi

if [[ -z $DOMAIN ]]; then
    error "域名不能为空"
fi

if [[ -d /data/bkce/weops/datart/config ]]; then
    warning "已经存在datart的配置文件, 跳过创建目录"
else
    install  -d -m 0644 /data/bkce/weops/datart/config
fi

if [[ -f /data/bkce/weops/datart/config/application-config.yml ]]; then
    warning "已经存在datart的配置文件, 文件将会被覆盖"  
fi

cat << EOF > /data/bkce/weops/datart/config/application-config.yml
spring:
  datasource:
    driver-class-name: com.mysql.cj.jdbc.Driver
    type: com.alibaba.druid.pool.DruidDataSource
    url: ${MYSQL_URL}
    username: ${MYSQL_USERNAME}
    password: ${MYSQL_PASSWORD}
server:
  port: 8080
  address: 0.0.0.0
  ssl:
    enabled: false
    key-store: keystore.p12 
    key-store-password: password
    keyStoreType: PKCS12
    keyAlias: tomcat

datart:
  migration:
    enable: true # 是否开启数据库自动升级
  server:
    address: http://datart.${DOMAIN}

  # 租户管理模式: platform-平台(默认),team-团队
  tenant-management-mode: platform

  user:
    register: false # 是否允许注册
    active:
      send-mail: false  # 注册用户时是否需要邮件验证激活
      expire-hours: 48 # 注册邮件有效期/小时
    invite:
      expire-hours: 48 # 邀请邮件有效期/小时

  security:
    token:
      secret: "d@a\$t%a^r&a*t1" #加密密钥
      timeout-min: 30  # 登录会话有效时长，单位：分钟。

  env:
    file-path: /root/files # 服务端文件保存位置

  screenshot:
    timeout-seconds: 60
    webdriver-type: CHROME
    webdriver-path: http://chrome:4444/wd/hub
EOF

# 检查是否有重复的容器
if [[ $(docker ps -a | grep datart) ]]; then
    warning "已经存在名为datart的容器，将会被删除"
    docker rm -f datart
fi

docker run -d -v /data/bkce/weops/datart/config/application-config.yml:/apps/config/profiles/application-config.yml:ro \
    --restart=always \
    --net=host \
    --name=datart \
    $DATART_IMAGE java -server -Xms2G -Xmx2G -Dspring.profiles.active=config -Dfile.encoding=UTF-8 -cp "lib/*" datart.DatartServerApplication 

if $INIT; then
    log save static file to /tmp/static.tgz
    docker cp datart:/apps/static/static /tmp/static && cd /tmp/ && tar -zcvf static.tgz static
    log save static file to /tmp/static.tgz success
fi