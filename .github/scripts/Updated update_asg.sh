#!/bin/bash

set -e

AMI_ID=$1
FRONTEND_ASG_NAME=$2
LAUNCH_TEMPLATE_NAME=$3

# Validate input parameters
if [ -z "$AMI_ID" ] || [ -z "$FRONTEND_ASG_NAME" ] || [ -z "$LAUNCH_TEMPLATE_NAME" ]; then
  echo "Error: Missing required parameters. Usage: $0 <AMI_ID> <FRONTEND_ASG_NAME> <LAUNCH_TEMPLATE_NAME>"
  exit 1
fi

if [[ ! "$AMI_ID" =~ ^ami-[a-f0-9]{8,17}$ ]]; then
  echo "Error: Invalid AMI ID: '$AMI_ID'"
  exit 1
fi

echo "Starting ASG update process with AMI ID: $AMI_ID"

ACTIVE_REFRESH=$(aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name $FRONTEND_ASG_NAME \
  --query 'InstanceRefreshes[?Status==`InProgress`].InstanceRefreshId' \
  --output text)

if [ -n "$ACTIVE_REFRESH" ]; then
  echo "Active refresh found. Waiting for it to complete..."
  aws autoscaling wait instance-refresh-in-progress \
    --auto-scaling-group-name $FRONTEND_ASG_NAME
  echo "Existing refresh completed. Proceeding with new update."
fi

ASG_CONFIG=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $FRONTEND_ASG_NAME \
  --query 'AutoScalingGroups[0]')

CURRENT_MIN=$(echo $ASG_CONFIG | jq -r '.MinSize')
CURRENT_MAX=$(echo $ASG_CONFIG | jq -r '.MaxSize')
CURRENT_DESIRED=$(echo $ASG_CONFIG | jq -r '.DesiredCapacity')

echo "Temporarily increasing Max Capacity to 2"
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $FRONTEND_ASG_NAME \
  --max-size 2

USER_DATA=$(cat << 'EOF' | base64 -w 0
#!/bin/bash
set -e
echo "Starting application..."
cd /home/ec2-user/app
pm2 start npm --name "heshbonaitplus" -- start
echo "Application started successfully."
EOF
)

echo "Creating new Launch Template version"
NEW_LAUNCH_TEMPLATE_VERSION=$(aws ec2 create-launch-template-version \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --source-version '$Latest' \
  --launch-template-data "{\"ImageId\":\"$AMI_ID\",\"UserData\":\"$USER_DATA\"}" \
  --query 'LaunchTemplateVersion.VersionNumber' \
  --output text)

echo "Updating ASG with new Launch Template version"
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $FRONTEND_ASG_NAME \
  --launch-template LaunchTemplateName=$LAUNCH_TEMPLATE_NAME,Version=$NEW_LAUNCH_TEMPLATE_VERSION

echo "Starting instance refresh"
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name $FRONTEND_ASG_NAME \
  --preferences '{"MinHealthyPercentage": 100}'

echo "Frontend Auto Scaling Group $FRONTEND_ASG_NAME updated with new AMI: $AMI_ID"

echo "Waiting for instance refresh to complete..."
while true; do
  REFRESH_STATUS=$(aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name $FRONTEND_ASG_NAME \
    --query 'InstanceRefreshes[0].Status' \
    --output text)
  
  if [ "$REFRESH_STATUS" = "Successful" ]; then
    echo "Instance refresh completed successfully!"
    break
  elif [ "$REFRESH_STATUS" = "Failed" ] || [ "$REFRESH_STATUS" = "Cancelled" ]; then
    echo "Instance refresh failed or was cancelled. Status: $REFRESH_STATUS"
    exit 1
  elif [ "$REFRESH_STATUS" = "InProgress" ]; then
    echo "Instance refresh still in progress. Current status: $REFRESH_STATUS"
    sleep 30
  else
    echo "Unexpected status: $REFRESH_STATUS. Checking again..."
    sleep 30
  fi
done

TARGET_GROUP_ARN=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $FRONTEND_ASG_NAME \
  --query 'AutoScalingGroups[0].TargetGroupARNs[0]' \
  --output text)

echo "Waiting 60 seconds before checking ALB health..."
sleep 60

TARGET_HEALTH=$(aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --query 'TargetHealthDescriptions[0].TargetHealth.State' \
  --output text)

if [ "$TARGET_HEALTH" != "healthy" ]; then
  echo "New instance is not healthy in ALB. Checking logs and application settings."
  exit 1
fi

echo "New instance is healthy in ALB."

echo "Restoring original ASG settings"
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $FRONTEND_ASG_NAME \
  --min-size $CURRENT_MIN \
  --max-size $CURRENT_MAX \
  --desired-capacity $CURRENT_DESIRED

echo "ASG update process completed successfully!"
