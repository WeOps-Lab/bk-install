#!/bin/bash
# Script Name: weops_components.sh
# Description: Script to install weops components
# Author: Jerko
# Created: 2023-09-05 00:18:13
# Version: 1.0
# Last Updated: 2023-09-05 00:18:13
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
  ["kafka-adapter"]="appt"
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

# Set up the log file
LOG_FILE=$IMAGE_DIR/deploy_kafka.log
echo "Starting WeOps components..." > $LOG_FILE

# Loop through the array and install and deploy each WeOps component
for COMPONENT_NAME in "${!COMPONENTS[@]}"
do
  NODE_ROLE=${COMPONENTS[$COMPONENT_NAME]}
  install_and_deploy_component "$COMPONENT_NAME" "$NODE_ROLE" $LOG_FILE
done

log "WeOps components deployment successfully completed." $LOG_FILE
