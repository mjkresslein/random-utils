#!/usr/bin/env bash
set -euo pipefail

# Requires: 
# AWSCLI (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and
# AWS Profiles configured
# Session manager plugin (sudo dnf install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm)
# Note: for profiles using sso `aws sso login` will need to be run prior to script


#################### SETTING AWS PROFILE ####################
# Get profiles into an array
mapfile -t profiles < <(aws configure list-profiles)

# Make sure at least one profile exists
if [[ ${#profiles[@]} -eq 0 ]]; then
    echo "No AWS profiles found."
    exit 1
fi

echo "Select an AWS profile:"
select AWS_PROFILE in "${profiles[@]}"; do
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "Using profile: $AWS_PROFILE"
        break
    fi
    echo "Invalid selection. Try again."
done

# Confirm profile being used -- REMOVE ME
aws sts get-caller-identity --profile "$AWS_PROFILE"


#################### GET INSTANCES ####################
# Prompt for a search filter
read -rp "Enter a search filter (optional): " SEARCH_FILTER

if [[ -n "$SEARCH_FILTER" ]]; then
    echo "Filtering by: $SEARCH_FILTER"
    mapfile -t instances < <(
        aws ec2 describe-instances \
            --profile "$AWS_PROFILE" \
            --filters \
                Name=instance-state-name,Values=running \
                "Name=tag:Name,Values=*${SEARCH_FILTER}*" \
            --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' \
            --output text
    )
else
    echo "No filter specified."
    mapfile -t instances < <(
        aws ec2 describe-instances \
            --profile "$AWS_PROFILE" \
            --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' \
            --output text
    )
fi

if [[ ${#instances[@]} -eq 0 ]]; then
    echo "No matching running instances found."
    exit 1
else    # -- REMOVE ME
    echo "instances found!"
fi


#################### SELECT AN INSTANCE ####################
echo "Select an instance:"
select instance in "${instances[@]}"; do
    if [[ -n "$instance" ]]; then
        INSTANCE_ID=$(awk '{print $1}' <<< "$instance")
        INSTANCE_NAME=$(cut -f2- <<< "$instance")
        break
    fi
    echo "Invalid selection. Try again."
done

echo "Selected instance: $INSTANCE_ID ($INSTANCE_NAME)"


#################### IDENTIFY AVAILABLE LOCAL ####################
BASE=3389

for ITER in {1..9}; do
    CANDIDATE="${ITER}${BASE}"

    if ! ss -ltn "( sport = :$CANDIDATE )" | grep -q ":$CANDIDATE"; then
        LOCAL_PORT="$CANDIDATE"
        break
    fi
done

if [[ -z $LOCAL_PORT ]]; then
    echo "No available ports in range..."
    exit 1
fi

echo "Using port: $CANDIDATE"


#################### START PORT-FWDING ####################
aws ssm start-session \
    --profile "$AWS_PROFILE" \
    --target $INSTANCE_ID \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{
        \"portNumber\":[\"3389\"],
        \"localPortNumber\":[\"$LOCAL_PORT\"]
    }"
