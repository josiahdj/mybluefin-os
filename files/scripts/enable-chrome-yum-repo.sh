#!/bin/bash

set -oue pipefail 

### Install Google Chrome from Official Repository
echo "Installing Google Chrome..."

# Add Google Chrome RPM repository
cat > /etc/yum.repos.d/google-chrome.repo << 'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

# Install Chrome
dnf5 install -y google-chrome-stable

# Clean up repo file (required - repos don't work at runtime in bootc images)
rm -f /etc/yum.repos.d/google-chrome.repo

echo "Google Chrome installed successfully"