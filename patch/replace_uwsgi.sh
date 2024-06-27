#!/bin/bash
source /data/install/utils.fc
scp uwsgi $BK_PAAS_IP:/tmp
source <(/opt/py36/bin/python /data/install/qq.py -p /data/src/open_paas/projects.yaml -P /data/install/bin/default/port.yaml)
projects=${_projects["paas"]}
for project in ${projects[@]};do
    ssh $BK_PAAS_IP "cp -av /tmp/uwsgi /data/bkce/.envs/open_paas-${project}/bin";
done
/data/install/bkcli restart paas