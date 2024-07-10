#!/bin/bash

set -e
echo "Starting Packer setup script..."

echo "Contents of /tmp/artifacts/:"
ls -l /tmp/artifacts/

# Update and upgrade system packages
echo "Updating system packages..."
sudo yum update -y

# Install Java 17
echo "Installing Java 17..."
sudo dnf install -y java-17-amazon-corretto

# Define variables
APP_DIR="/home/ec2-user/app"
ARTIFACT_DIR="/tmp/artifacts"  # This should match Packer's configuration
JAR_NAME=$(ls ${ARTIFACT_DIR}/*.jar | head -1)  # This will get the name of the first JAR file in the artifacts directory

echo "Contents of ${ARTIFACT_DIR}:"
ls -l ${ARTIFACT_DIR}


# Ensure app directory exists
sudo mkdir -p ${APP_DIR}

# Copy the JAR file from the artifact directory to the app directory
echo "Copying JAR file to application directory..."
sudo cp ${JAR_NAME} ${APP_DIR}/
echo "Contents of ${APP_DIR} after copy:"
ls -l ${APP_DIR}

echo "Contents of ${APP_DIR} after copy:"
ls -l ${APP_DIR}

# Get just the filename of the JAR
JAR_FILENAME=$(basename ${JAR_NAME})

# Ensure correct permissions
sudo chown ec2-user:ec2-user ${APP_DIR}/${JAR_FILENAME}
sudo chmod 644 ${APP_DIR}/${JAR_FILENAME}

# Create a startup script
echo "Creating startup script..."
cat << EOF | sudo tee /home/ec2-user/start_app.sh
#!/bin/bash
cd ${APP_DIR}
java -jar ${JAR_FILENAME}
EOF

sudo chmod +x /home/ec2-user/start_app.sh

# Set up the application to start on boot using systemd
echo "Setting up systemd service..."
cat << EOF | sudo tee /etc/systemd/system/myapp.service
[Unit]
Description=My Java Application
After=network.target

[Service]
ExecStart=/home/ec2-user/start_app.sh
User=ec2-user
WorkingDirectory=${APP_DIR}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "Final contents of ${APP_DIR}:"
ls -l ${APP_DIR}

# Enable the service
sudo systemctl enable myapp.service
echo "Starting the application service..."
sudo systemctl start myapp.service

echo "Packer setup completed successfully."