#!/bin/bash
# Set execute permissions for the script
chmod +x "$0"
set -e

AMI_ID=$1
FRONTEND_ASG_NAME=$2
LAUNCH_TEMPLATE_NAME=$3

# הגדרת משתנים לתיקיית האפליקציה ו-URL של המאגר
REPO_PATH="/home/ec2-user/app"
REPO_URL="https://github.com/dvirmoyal/learn-packer-github-actions.git"

echo "Starting ASG update process with AMI ID: $AMI_ID"

# Check if Launch Template exists
if ! aws ec2 describe-launch-templates --launch-template-names "$LAUNCH_TEMPLATE_NAME" > /dev/null 2>&1; then
    echo "Error: Launch Template $LAUNCH_TEMPLATE_NAME does not exist."
    echo "Please create the Launch Template manually with the required settings before running this script."
    exit 1
else
    echo "Launch Template $LAUNCH_TEMPLATE_NAME exists. Proceeding with update."
fi

echo "Temporarily increasing Max Capacity to 2"
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $FRONTEND_ASG_NAME \
  --max-size 2

echo "Creating new Launch Template version"
LATEST_LAUNCH_TEMPLATE=$(aws ec2 describe-launch-template-versions \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData' \
  --output json)

# Update only the AMI ID in the new version
NEW_LAUNCH_TEMPLATE_DATA=$(echo $LATEST_LAUNCH_TEMPLATE | jq --arg AMI_ID "$AMI_ID" '.ImageId = $AMI_ID')

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

# Get the ID of the new instance
NEW_INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $FRONTEND_ASG_NAME \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
  --output text | awk '{print $NF}')

echo "New instance ID: $NEW_INSTANCE_ID"

# Wait for the instance to be fully initialized
echo "Waiting for instance to be fully initialized..."
aws ec2 wait instance-status-ok --instance-ids $NEW_INSTANCE_ID

# Update application on the new instance
echo "Updating application on the new instance..."
aws ssm send-command \
  --instance-ids $NEW_INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{
    "commands":[
      "mkdir -p '"$REPO_PATH"'",
      "cd '"$REPO_PATH"'",
      "git clone '"$REPO_URL"' .",
      "npm install",
      "pm2 restart all || pm2 start app.js"
    ]
  }'

# Check if the application is running
echo "Checking if the application is running..."
APP_STATUS=$(aws ssm send-command \
  --instance-ids $NEW_INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["pm2 list"]}' \
  --output text --query "CommandInvocations[0].CommandPlugins[0].Output")

if [[ $APP_STATUS != *"online"* ]]; then
  echo "Application is not running. Attempting to start..."
  aws ssm send-command \
    --instance-ids $NEW_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters '{"commands":["cd '"$REPO_PATH"' && pm2 start app.js"]}'
  
  # Wait a bit and check again
  sleep 30
  APP_STATUS=$(aws ssm send-command \
    --instance-ids $NEW_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters '{"commands":["pm2 list"]}' \
    --output text --query "CommandInvocations[0].CommandPlugins[0].Output")
  
  if [[ $APP_STATUS != *"online"* ]]; then
    echo "Failed to start the application. Please check the instance manually."
    exit 1
  fi
fi

echo "Application is running."

TARGET_GROUP_ARN=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $FRONTEND_ASG_NAME \
  --query 'AutoScalingGroups[0].TargetGroupARNs[0]' \
  --output text)

echo "Waiting 90 seconds before checking ALB health..."
sleep 90

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
