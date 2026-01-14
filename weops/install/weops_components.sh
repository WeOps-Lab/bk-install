#!/bin/bash
# Script Name: weops_components.sh
# Description: Script to install weops components
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

# Define the directory where your WeOps components and install scripts are stored
source /data/install/utils.fc
IMAGE_DIR=/data/weops/components

# Define an array of WeOps components and their corresponding node roles
declare -A COMPONENTS=(
  ["remote-service"]="appt"
  ["minio"]="appo"
  ["prometheus"]="appt"
  ["automate"]="appt"
  ["ssr-echarts"]="appt"
  ["weops-proxy"]="appt"
  ["casbin-mesh"]="appo"
)

# Function to log messages to console and to a log file
log() {
  local MESSAGE=$1
  local LOG_FILE=$2
  
  # Print the message to console
  echo "$MESSAGE"

  # Append the message to the log file
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $MESSAGE" >> $LOG_FILE
}


# Function to install and deploy a WeOps component
install_and_deploy_component() {
  local COMPONENT_NAME=$1
  local NODE_ROLE=$2
  local LOG_FILE=$3
  
  # Go to the directory for the current WeOps component
  cd "$IMAGE_DIR/$COMPONENT_NAME"
  
  log "$COMPONENT_NAME Started and deploying  on $NODE_ROLE..." $LOG_FILE

  # Set the backup IP address based on the node role
  if [[ $NODE_ROLE == "appo" ]]; then
    NODE_ROLE_IP=$BK_APPO_IP
  elif [[ $NODE_ROLE == "appt" ]]; then
    NODE_ROLE_IP=$BK_APPT_IP
  else
    log "Invalid node role: $NODE_ROLE" $LOG_FILE
    return 2
  fi

  if [[ $COMPONENT_NAME == "automate" ]]; then
    # Run the install script for the automate component
    /data/install/pcmd.sh -m "$NODE_ROLE" "mkdir -p $IMAGE_DIR/$COMPONENT_NAME"
    scp "$IMAGE_DIR/$COMPONENT_NAME/"* "$NODE_ROLE_IP:$IMAGE_DIR/$COMPONENT_NAME"
    ${CTRL_DIR}/pcmd.sh -H $NODE_ROLE_IP "docker load < /data/weops/components/automate/vault.tgz && docker load < /data/weops/components/automate/auto-mate_v1.0.21-fix2.tgz"
    cd "$IMAGE_DIR/$COMPONENT_NAME" && bash "$IMAGE_DIR/$COMPONENT_NAME/${COMPONENT_NAME}_install.sh"
  else
    # Run the install script for the current WeOps component
    /data/install/pcmd.sh -m "$NODE_ROLE" "mkdir -p $IMAGE_DIR/$COMPONENT_NAME"
    scp "$IMAGE_DIR/$COMPONENT_NAME/"* "$NODE_ROLE_IP:$IMAGE_DIR/$COMPONENT_NAME"
    /data/install/pcmd.sh -m "$NODE_ROLE" "cd $IMAGE_DIR/$COMPONENT_NAME && bash $IMAGE_DIR/$COMPONENT_NAME/${COMPONENT_NAME}_install.sh"
  fi

  log "$COMPONENT_NAME installation and deployment on $NODE_ROLE successfully completed." $LOG_FILE
}


install_age () {
    source /data/install/utils.fc
    ssh $BK_APPT_IP "mkdir -p /data/weops/age/data/"
cat <<EOF > /data/install/bin/04-final/age.env
AGE_DB_HOST=${BK_APPT_IP}
AGE_DB_PORT=5432
AGE_DB_NAME=weops
AGE_DB_USER=weops
AGE_DB_PASSWORD=$(rndpw 16)
EOF
    /data/install/bkcli sync common
    source /data/install/utils.fc
cat << EOF > /data/weops/components/age/docker-compose.yaml
services:
  age:
    image: docker-bkrepo.cwoa.net/ce1b09/weops-docker/age:PG16-1.1.5
    environment:
      POSTGRES_USER: ${AGE_DB_USER}
      POSTGRES_PASSWORD: ${AGE_DB_PASSWORD}
      PGDATA: /data/postgres
      POSTGRES_DB: ${AGE_DB_NAME}
    volumes:
      - ./data:/data/postgres
    network_mode: host
    restart: always
EOF
    scp /data/weops/components/age/* $BK_APPT_IP:/data/weops/age/
    scp $(find /data/install/yum/ -name docker-compose) $BK_APPT_IP:/usr/local/bin/
    ssh $BK_APPT_IP "docker load < /data/weops/age/age_PG16-1.1.5.tgz"
    ssh $BK_APPT_IP "source /data/install/utils.fc && docker-compose -f /data/weops/age/docker-compose.yaml up -d"
}
install_age


install_monstache () {
    source /data/install/utils.fc
    ssh $BK_APPT_IP "mkdir -p /data/weops/monstache/"
cat << EOF > /data/weops/components/monstache/start_monstache.sh
docker rm -f monstache
docker run --net=host -itd \
    --name=monstache \
    --privileged=true \
    -e BK_CMDB_MONGODB_PASSWORD=$BK_CMDB_MONGODB_PASSWORD \
    -e BK_CMDB_ES7_PASSWORD=$BK_ES7_ADMIN_PASSWORD \
    docker-bkrepo.cwoa.net/ce1b09/weops-docker/monstache:latest
EOF
    scp /data/weops/components/monstache/* $BK_APPT_IP:/data/weops/monstache/
    ssh $BK_APPT_IP "docker load < /data/weops/monstache/monstache_latest.tgz"
    ssh $BK_APPT_IP "source /data/install/utils.fc && bash /data/weops/monstache/start_monstache.sh"
}
install_monstache


install_vector () {
    source /data/install/utils.fc
    ssh $BK_APPT_IP "mkdir -p /data/weops/vector/"
    scp /data/weops/components/vector/* $BK_APPT_IP:/data/weops/vector/
    ssh $BK_APPT_IP "docker load < /data/weops/vector/vector_0.34.1-debian.tgz"
    ssh $BK_APPT_IP "source /data/install/utils.fc && bash /data/weops/vector/start_vector.sh"
}
install_vector


# Set up the log file
LOG_FILE=$IMAGE_DIR/deploy.log
echo "Starting WeOps components..." > $LOG_FILE

# Loop through the array and install and deploy each WeOps component
for COMPONENT_NAME in "${!COMPONENTS[@]}"
do
  NODE_ROLE=${COMPONENTS[$COMPONENT_NAME]}
  install_and_deploy_component "$COMPONENT_NAME" "$NODE_ROLE" $LOG_FILE
done

log "WeOps components deployment successfully completed." $LOG_FILE
