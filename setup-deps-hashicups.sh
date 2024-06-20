#!/bin/bash

sleep 30
set -e

echo "Starting installation script..."

# Update and upgrade system packages
echo "Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Install required packages
echo "Installing required packages..."
sudo apt install -y git wget ruby

# Install CodeDeploy Agent
echo "Installing CodeDeploy Agent..."
cd /home/ubuntu
wget https://aws-codedeploy-il-central-1.s3.il-central-1.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto

# Install Node.js and npm
echo "Installing Node.js and npm..."
curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install PM2 globally
echo "Installing PM2 globally..."
sudo npm install -g pm2

# Define variables
GITHUB_USER="HeshbonaitP"
GITHUB_REPO="Frontend"
GITHUB_BRANCH="develop"
GITHUB_PAT="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"
APP_DIR="/home/ubuntu/app"

# Clone the specific branch from GitHub
echo "Cloning the repository..."
git clone -b ${GITHUB_BRANCH} https://${GITHUB_USER}:${GITHUB_PAT}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git ${APP_DIR}

# Change directory to the app
cd ${APP_DIR}

# Install app dependencies
echo "Installing app dependencies..."
npm install

# Build the app
echo "Building the app..."
npm run build

# Start the app with PM2
echo "Starting the app with PM2..."
pm2 start npm --name "heshbonaitplus" -- start

# Save running processes and set up PM2 to start on boot
echo "Saving running processes and setting up PM2 to start on boot..."
pm2 save
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu

echo "Installation script completed."
