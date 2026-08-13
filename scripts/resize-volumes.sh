#!/bin/bash


SEARCH_STRING="physna"
ORIG_VOL_SIZE="70"
NEW_VOL_SIZE="350"
VOLUMES_LIST=()



echo -e "\n\n"
echo -e "======================================================"
echo -e " Getting ${SEARCH_STRING} instances"
echo -e "======================================================"

list-running-instances() {
    aws ec2 describe-instances \
        --filters Name=instance-state-name,Values=running Name=tag:Name,Values=*-${SEARCH_STRING}-*-blue \
        --query "Reservations[*].Instances[*].{Name: Tags[?Key=='Name']|[0].Value,InstanceId: InstanceId}" \
        --output table
}

list-running-instances

readarray -t INSTANCE_IDS < <(
    aws ec2 describe-instances \
        --filters Name=instance-state-name,Values=running Name=tag:Name,Values=*-${SEARCH_STRING}-* \
        --output json | jq -r '.Reservations[].Instances[].InstanceId'
)

# echo -e "${INSTANCE_IDS[@]}"

echo -e "\n\n"
echo -e "======================================================"
echo -e " Getting ${SEARCH_STRING} instance volumes"
echo -e "======================================================"

for instance_id in "${INSTANCE_IDS[@]}"; do
    echo -e "\nInstance ID:\t${instance_id}"
    aws ec2 describe-volumes \
        --filters Name=attachment.instance-id,Values=${instance_id} \
            Name=size,Values=${ORIG_VOL_SIZE} \
        --query "Volumes[].{ID:VolumeId,Size:Size,Type:VolumeType,Device:Attachments[0].Device}" \
        --output table
    VOLUMES_LIST+=($(
        aws ec2 describe-volumes \
            --filters Name=attachment.instance-id,Values=${instance_id} \
                Name=size,Values=${ORIG_VOL_SIZE} \
            --output json | jq -r '.Volumes[].VolumeId'
    ))
done

# echo -e "\n${VOLUMES_LIST[@]}"

echo -e "\n\n"
echo -e "======================================================"
echo -e " Resizing ${SEARCH_STRING} instance volumes"
echo -e "======================================================"

for vol_id in "${VOLUMES_LIST[@]}"; do
    echo -e "\nVolume ID:\t${vol_id}"
    aws ec2 modify-volume \
        --volume-id ${vol_id} \
        --size ${NEW_VOL_SIZE}
    
    sleep 5
    
    aws ec2 describe-volumes \
        --volume-ids ${vol_id} \
        --query "Volumes[].{ID:VolumeId,Size:Size,Type:VolumeType,Device:Attachments[0].Device}" \
        --output table
done

echo -e "\n\n"
echo -e "======================================================"
echo -e " Resizing ${SEARCH_STRING} instance partitions"
echo -e "======================================================"

for instance_id in "${INSTANCE_IDS[@]}"; do
    echo -e "\nInstance ID:\t${instance_id}"
    COMMAND_ID=$(
        aws ssm send-command \
            --instance-ids ${instance_id} \
            --document-name "AWS-RunShellScript" \
            --parameters commands='[
                "pvresize /dev/nvme1n1",
                "lvextend -l +100%FREE /dev/RootVG/varVol",
                "lvdisplay /dev/RootVG/varVol",
                "resize2fs /dev/RootVG/varVol",
                "df -h | grep varVol"
            ]' \
            --query "Command.CommandId" \
            --output text
    )
    
    sleep 3

    aws ssm get-command-invocation \
        --command-id ${COMMAND_ID} \
        --instance-id ${instance_id} \
        --query "StandardOutputContent" \
        --output text
done
