#!/bin/bash
# Set execute permissions for the script
chmod +x "$0"
set -e

AMI_ID=$1
FRONTEND_ASG_NAME=$2
LAUNCH_TEMPLATE_NAME=$3

# Define variables for the Java application
APP_DIR="/home/ec2-user/app"
JAR_FILE=$(ls $APP_DIR/*.jar | head -n 1)  # Assumes the JAR file is in the app directory
JAVA_VERSION="17"
JAVA_OPTS="-Xmx512m -Dspring.profiles.active=production -Dspring.jpa.hibernate.ddl-auto=none -Dspring.jpa.properties.hibernate.temp.use_jdbc_metadata_defaults=false"

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

echo "Checking for JAR file..."
JAR_CHECK=$(aws ssm send-command \
  --instance-ids $NEW_INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["ls -l /home/ec2-user/app/*.jar"]}' \
  --output text --query "CommandInvocations[0].CommandPlugins[0].Output")

if [[ $JAR_CHECK == *"No such file or directory"* ]]; then
  echo "JAR file not found in /home/ec2-user/app/. Please check your AMI and deployment process."
  exit 1
fi

echo "JAR file found. Proceeding with application start..."

# Wait for the instance to be fully initialized
echo "Waiting for instance to be fully initialized..."
aws ec2 wait instance-status-ok --instance-ids $NEW_INSTANCE_ID

echo "Starting Java application on the new instance..."
aws ssm send-command \
  --instance-ids $NEW_INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{
    "commands":[
      "cd '"$APP_DIR"'",
      "JAR_FILE=$(ls *.jar | head -n 1)",
      "nohup java -version '"$JAVA_VERSION"' '"$JAVA_OPTS"' -jar $JAR_FILE > app.log 2>&1 &",
      "echo $! > app.pid"
    ]
  }'

echo "Waiting 60 seconds for the application to start..."
sleep 60

echo "Checking for JAR file..."
JAR_CHECK=$(aws ssm send-command \
  --instance-ids $NEW_INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["ls -l /home/ec2-user/app/*.jar"]}' \
  --output text --query "CommandInvocations[0].CommandPlugins[0].Output")

if [[ $JAR_CHECK == *"No such file or directory"* ]]; then
  echo "JAR file not found in /home/ec2-user/app/. Please check your AMI and deployment process."
  exit 1
fi

echo "JAR file found. Proceeding with application start..."


# Check if the application is running
echo "Checking if the application is running..."
APP_STATUS=$(aws ssm send-command \
  --instance-ids $NEW_INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["ps aux | grep java | grep -v grep"]}' \
  --output text --query "CommandInvocations[0].CommandPlugins[0].Output")

if [[ -z "$APP_STATUS" ]]; then
  echo "Java application is not running. Checking logs..."
  aws ssm send-command \
    --instance-ids $NEW_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters '{"commands":["tail -n 50 '"$APP_DIR"'/app.log"]}'
  echo "Failed to start the Java application. Please check the instance manually."
  exit 1
fi

echo "Java application is running."

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
  echo "New instance is not healthy in ALB. Checking application logs..."
  aws ssm send-command \
    --instance-ids $NEW_INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters '{"commands":["tail -n 100 '"$APP_DIR"'/app.log"]}'
  echo "Please check the application settings and ALB health check configuration."
  exit 1
fi

echo "Checking contents of /home/ec2-user/app/ in the new instance:"
aws ssm send-command \
  --instance-ids $NEW_INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["ls -l /home/ec2-user/app/"]}' \
  --output text --query "CommandInvocations[0].CommandPlugins[0].Output"
  
echo "New instance is healthy in ALB."
echo "ASG update process completed successfully!"