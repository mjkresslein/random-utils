#!/usr/bin/env bash
set -euo pipefail

#################### Display usage message ####################
usage() {
    echo -e "\n Usage: "
    echo -e "\t $0 <search_string> <rds_instance_name> \n"
    exit 1
}

#################### Check if arguments are provided ####################
if [[ $# -lt 1 ]]; then
    usage
fi

#################### Bind variables ####################
SEARCH_STRING=""
RDS_INSTANCE_NAME=""

#################### Parse args ####################
while [[ $# -gt 0 ]]; do
    if [[ -z "$SEARCH_STRING" ]]; then
        SEARCH_STRING="$1"
    elif [[ -z "$RDS_INSTANCE_NAME" ]]; then
        RDS_INSTANCE_NAME="$1"
    else
        echo "Unknown argument: $1"
        exit 1
    fi
    shift
done

#################### Set defaults ####################
RDS_INSTANCE_NAME="${RDS_INSTANCE_NAME:-lcmp-fol-waypoint-ai-rds}"
LOCAL_PORT="5432"

echo "Search string is: $SEARCH_STRING"
echo "Instance name is: $RDS_INSTANCE_NAME"

#################### Find an AMI given the search filter string ####################
TARGET_INSTANCE=$(aws ec2 describe-instances \
    --filters Name=instance-state-name,Values=running Name=tag:Name,Values=*-${SEARCH_STRING}-*-blue \
    --output json \
    | jq -r '.Reservations[0].Instances[].InstanceId')
echo "Target Instance is: $TARGET_INSTANCE"

#################### Get RDS Instance endpoint ####################

INSTANCE_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier ${RDS_INSTANCE_NAME} \
    --query "DBInstances[0].Endpoint.Address" \
    --output text)
echo "Instance endpoint is: $INSTANCE_ENDPOINT"

# HOST_ONLY=${INSTANCE_ENDPOINT#https://}
# echo "Instance host address is: $HOST_ONLY"

#################### Set up a port forwarding session with the AMI identified ####################
aws ssm start-session \
    --target $TARGET_INSTANCE \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{
        \"portNumber\":[\"5432\"],
        \"localPortNumber\":[\"$LOCAL_PORT\"],
        \"host\":[\"$INSTANCE_ENDPOINT\"]
    }"
