#!/usr/bin/env bash
# Description: check service's health wrapper

set -euo pipefail
SELF_DIR=$(dirname "$(readlink -f "$0")")

# 加载load_env和通用函数
source "${SELF_DIR}"/tools.sh

BK_PKG_SRC_PATH=${BK_PKG_SRC_PATH:-/data/src}
BK_HOME=${BK_HOME:-/data/bkee}
PCMD=${SELF_DIR}/pcmd.sh

SUPPORT_MODULE=(bkssm bkiam usermgr paas cmdb gse job consul bklog dbcheck bkmonitorv3 bkapi)
usage () {
    echo "$0 <module>"
    echo "The supported modules are: ${SUPPORT_MODULE[@]}"
    exit 1
}
[[ $# == 0 ]] && usage

MODULE=$1
case $MODULE in
    bkssm|bkiam|usermgr) $PCMD -m "${MODULE#bk}" "$SELF_DIR/health_check/check_consul_svc_health.sh $MODULE" ;;
    paas|cmdb) $PCMD -m "$MODULE" "$SELF_DIR/health_check/check_consul_svc_health.sh ^${MODULE}-" ;;
    gse|license) $PCMD -m gse "$CTRL_DIR/health_check/check_${MODULE}.sh" ;;
    job)
        step "check job backend health"
        $PCMD -m job '$CTRL_DIR/health_check/check_job.sh'
        step "check job frontend resource"
        $PCMD -m nginx 'runuser -u blueking -- ls -l $BK_HOME/job/frontend/index.html'
        ;;
    consul) $PCMD -m all '$CTRL_DIR/health_check/check_consul_resolv.sh' ;;
    rabbitmq) $PCMD -m rabbitmq 'rabbitmq-diagnostics -q check_running && rabbitmq-diagnostics -q check_local_alarms' ;;
    bklog) $PCMD -m ${MODULE#bk} "$SELF_DIR/health_check/check_consul_svc_health.sh $MODULE" ;;
    bkmonitorv3|monitorv3) $PCMD -H $BK_MONITORV3_MONITOR_IP 'workon bkmonitorv3-monitor; ./bin/manage.sh healthz' ;;
    nginx) $PCMD -m nginx '$CTRL_DIR/health_check/check_openresty.sh' ;;
    weopsconsul) $PCMD -m weopsconsul "$CTRL_DIR/health_check/check_weops_component.sh ${MODULE}" ;;
    dbcheck)
        set +u
        [[ -f ${HOME}/.bkrc ]] && source ${HOME}/.bkrc
        workon deploy_check && python ${SELF_DIR}/health_check/deploy_check.py  -d "${SELF_DIR}/bin/04-final" -m "cmdb,paas,ssm,bkiam,usermgr,gse,job,bknodeman,bkmonitorv3"
        ;;
    bkapi)
        # 支持的模块 bk_cmdb, bk_job, bk_gse, bk_itsm, bk_monitorv3, bk_paas, bk_sops, bk_user_manage
        cost_time_attention
        $PCMD -m nginx "$SELF_DIR/health_check/check_bkapi.sh ${2:-all}"
        ;;
    --list)
        printf "%s\n" "${SUPPORT_MODULE[@]}"
        ;;
    *) usage ;;
esac
