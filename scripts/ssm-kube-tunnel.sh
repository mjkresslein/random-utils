#!/usr/bin/env bash
set -euo pipefail

### Display usage message
usage() {
    echo -e "\n Usage: "
    echo -e "\t $0 <search_string> <cluster_name> \n"
    exit 1
}

### Check if arguments are provided
if [[ $# -lt 1 ]]; then
    usage
fi

### Bind variables
SEARCH_STRING=""
CLUSTER_NAME=""

### Parse args
while [[ $# -gt 0 ]]; do
    if [[ -z "$SEARCH_STRING" ]]; then
        SEARCH_STRING="$1"
    elif [[ -z "$CLUSTER_NAME" ]]; then
        CLUSTER_NAME="$1"
    else
        echo "Unknown argument: $1"
        exit 1
    fi
    shift
done

### Set defaults
CLUSTER_NAME="${CLUSTER_NAME:-strata-eks-133-blue}"
LOCAL_PORT="8443"

echo "Search string is: $SEARCH_STRING"
echo "Cluster name is: $CLUSTER_NAME"

### Find an AMI given the search filter string
TARGET_INSTANCE=$(aws ec2 describe-instances \
    --filters Name=instance-state-name,Values=running Name=tag:Name,Values=*-${SEARCH_STRING}-*-blue \
    --output json \
    | jq -r '.Reservations[0].Instances[].InstanceId')
echo "Target Instance is: $TARGET_INSTANCE"

### Get EKS cluster endpoint

CLUSTER_ENDPOINT=$(aws eks describe-cluster \
    --name ${CLUSTER_NAME} \
    --query "cluster.endpoint" \
    --output text)
echo "Cluster endpoint is: $CLUSTER_ENDPOINT"

HOST_ONLY=${CLUSTER_ENDPOINT#https://}
echo "Cluster host address is: $HOST_ONLY"

### Set up a port forwarding session with the AMI identified
aws ssm start-session \
    --target $TARGET_INSTANCE \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{
        \"portNumber\":[\"443\"],
        \"localPortNumber\":[\"$LOCAL_PORT\"],
        \"host\":[\"$HOST_ONLY\"]
    }"
