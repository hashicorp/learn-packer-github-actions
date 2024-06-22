#!/bin/bash

sleep 30
set -e
echo "Starting installation script..."

# Update and upgrade system packages
echo "Updating system packages..."
sudo yum update -y

# Install required packages
echo "Installing required packages..."
sudo yum install -y git wget ruby

# Install Node.js and npm
echo "Installing Node.js and npm..."
curl -sL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# Install PM2 globally
echo "Installing PM2 globally..."
sudo npm install -g pm2

# Define variables
GITHUB_USER="dvirmoyal"
GITHUB_REPO="Frontend"
GITHUB_BRANCH="develop"
APP_DIR="/home/ec2-user/app"

# Ensure SSH agent is running and add the key
eval $(ssh-agent -s)
ssh-add /home/ec2-user/.ssh/id_ed25519

# Set up SSH config to use the correct key for GitHub
mkdir -p ~/.ssh
echo "Host github.com
    IdentityFile /home/ec2-user/.ssh/id_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking no" > ~/.ssh/config

# Ensure correct permissions on SSH files
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 /home/ec2-user/.ssh/id_ed25519

# Clone the specific branch from GitHub
echo "Cloning the repository..."
git clone -b ${GITHUB_BRANCH} git@github.com:${GITHUB_USER}/${GITHUB_REPO}.git ${APP_DIR}

# Check if clone was successful
if [ $? -eq 0 ]; then
    echo "Repository cloned successfully."
else
    echo "Failed to clone repository. Please check your SSH key and GitHub access."
    exit 1
fi

# Change directory to the app
cd ${APP_DIR}

# Install app dependencies
echo "Installing app dependencies..."
npm install

# Build the app
echo "Building the app..."
npm run build

# Create a startup script
cat << EOF > /home/ec2-user/start_app.sh
#!/bin/bash
cd ${APP_DIR}
pm2 start npm --name "heshbonaitplus" -- start
EOF

chmod +x /home/ec2-user/start_app.sh

# Add the startup script to crontab
echo "@reboot ec2-user /home/ec2-user/start_app.sh" | sudo tee -a /etc/crontab

echo "Installation script completed."