#!/bin/bash

set -e
echo "Starting Packer setup script..."

JAR_PATH="/tmp/app.jar"

if [ ! -f "$JAR_PATH" ]; then
  echo "Error: JAR file not found at $JAR_PATH"
  exit 1
fi

# Define variables
APP_DIR="/opt/myapp"
JAR_FILENAME=$(basename ${JAR_PATH})

echo "JAR_PATH is: ${JAR_PATH}"
echo "JAR_FILENAME is: ${JAR_FILENAME}"
echo "Contents of /tmp:"
ls -la /tmp

# Ensure app directory exists and copy JAR
echo "Creating ${APP_DIR} and copying JAR..."
sudo mkdir -p ${APP_DIR}
sudo cp ${JAR_PATH} ${APP_DIR}/
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

echo "Packer setup completed successfully."