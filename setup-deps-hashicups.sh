#!/bin/bash

set -e
echo "Starting Packer setup script..."

if [ ! -f "${ARTIFACT_DIR}/*.jar" ]; then
  echo "Error: No JAR file found in ${ARTIFACT_DIR}"
  exit 1
fi

# Define variables
APP_DIR="/opt/myapp"
ARTIFACT_DIR="/tmp/artifacts"
JAR_NAME=$(find ${ARTIFACT_DIR} -type f -name '*.jar' | head -1)
JAR_FILENAME=$(basename ${JAR_NAME})

echo "Contents of ${ARTIFACT_DIR}:"
ls -l ${ARTIFACT_DIR}

# Update and upgrade system packages
echo "Updating system packages..."
sudo yum update -y

# Install Java 17
echo "Installing Java 17..."
sudo dnf install -y java-17-amazon-corretto

# Ensure app directory exists and copy JAR
echo "Creating ${APP_DIR} and copying JAR..."
sudo mkdir -p ${APP_DIR}
sudo cp ${JAR_NAME} ${APP_DIR}/
sudo chown -R ec2-user:ec2-user ${APP_DIR}
sudo chmod 644 ${APP_DIR}/${JAR_FILENAME}

echo "Contents of ${APP_DIR} after copy:"
ls -l ${APP_DIR}

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

sudo systemctl enable myapp.service

echo "Final contents of ${APP_DIR}:"
ls -l ${APP_DIR}

# Create a script that will run on instance launch (simulating User Data)
echo "Creating instance launch script..."
cat << EOF | sudo tee /opt/instance_launch.sh
#!/bin/bash

# Ensure the application directory exists
APP_DIR="${APP_DIR}"
sudo mkdir -p \${APP_DIR}
sudo chown ec2-user:ec2-user \${APP_DIR}

# Check if JAR file exists and start the service
if [ -f "\${APP_DIR}"/*.jar ]; then
  echo "JAR file found. Starting the service..."
  sudo systemctl start myapp.service
else
  echo "Error: JAR file not found in \${APP_DIR}"
fi

echo "Instance launch setup completed."
EOF

sudo chmod +x /opt/instance_launch.sh

# Add the launch script to run at instance boot
echo "Adding launch script to run at boot..."
sudo sed -i '/^exit 0/i /opt/instance_launch.sh' /etc/rc.local
sudo chmod +x /etc/rc.local

echo "Packer setup completed successfully."