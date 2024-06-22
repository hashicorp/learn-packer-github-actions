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
GITHUB_PAT="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"
APP_DIR="/home/ec2-user/app"

# Clone the specific branch from GitHub
echo "Cloning the repository..."
git clone -b ${GITHUB_BRANCH} git@github.com:${GITHUB_USER}/${GITHUB_REPO}.git ${APP_DIR}

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
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ec2-user --hp /home/ec2-user

echo "Installation script completed."