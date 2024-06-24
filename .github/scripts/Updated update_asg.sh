#!/bin/bash

# Set execute permissions for the script
chmod +x "$0"

set -e

AMI_ID=$1
FRONTEND_ASG_NAME=$2
LAUNCH_TEMPLATE_NAME=$3
INSTANCE_TYPE="t3.micro"

echo "Starting ASG update process with AMI ID: $AMI_ID"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Using alternative method."
    JQ_INSTALLED=false
else
    JQ_INSTALLED=true
fi

# Check if Launch Template exists
if ! aws ec2 describe-launch-templates --launch-template-names "$LAUNCH_TEMPLATE_NAME" > /dev/null 2>&1; then
    echo "Launch Template $LAUNCH_TEMPLATE_NAME does not exist. Creating it..."
    aws ec2 create-launch-template \
        --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
        --version-description "Initial version" \
        --launch-template-data "{\"ImageId\":\"$AMI_ID\",\"InstanceType\":\"$INSTANCE_TYPE\"}"
    echo "Launch Template created successfully."
else
    echo "Launch Template $LAUNCH_TEMPLATE_NAME exists. Proceeding with update."
fi

echo "Temporarily increasing Max Capacity to 2"
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $FRONTEND_ASG_NAME \
  --max-size 2

echo "Creating new Launch Template version"
if $JQ_INSTALLED; then
    LATEST_LAUNCH_TEMPLATE=$(aws ec2 describe-launch-template-versions \
      --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
      --versions '$Latest' \
      --query 'LaunchTemplateVersions[0].LaunchTemplateData' \
      --output json)

    NEW_LAUNCH_TEMPLATE_DATA=$(echo $LATEST_LAUNCH_TEMPLATE | jq --arg AMI_ID "$AMI_ID" '.ImageId = $AMI_ID')
else
    # Alternative method without jq
    LATEST_LAUNCH_TEMPLATE=$(aws ec2 describe-launch-template-versions \
      --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
      --versions '$Latest' \
      --query 'LaunchTemplateVersions[0].LaunchTemplateData' \
      --output text)

    NEW_LAUNCH_TEMPLATE_DATA="{\"ImageId\":\"$AMI_ID\",\"InstanceType\":\"$INSTANCE_TYPE\"}"
fi

NEW_LAUNCH_TEMPLATE_VERSION=$(aws ec2 create-launch-template-version \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --launch-template-data "$NEW_LAUNCH_TEMPLATE_DATA" \
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

echo "ASG update process completed successfully!"
