#!/bin/bash
# Script to install Foreman with Proxmox, Ansible plugins on AlmaLinux 9
# Foreman 3.13 Stable with the option to install Nightly
# Proxmox Hypervisor 8.3 (API v2)
# AlmaLinux 9.5
# Netbird 0.34.0 Overlay Network

# Function to get primary IP address
get_primary_ip() {
    # First try to get IP from the default route interface
    PRIMARY_IP=$(ip route get 1 | awk '{print $7;exit}')
    
    # If that fails, try to get the first non-localhost IP
    if [ -z "$PRIMARY_IP" ]; then
        PRIMARY_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    echo "$PRIMARY_IP"
}

# Get the IP address
IP_ADDRESS=$(get_primary_ip)

# Verify we got an IP address
if [ -z "$IP_ADDRESS" ]; then
    echo "ERROR: Could not determine IP address"
    exit 1
fi

echo "Detected IP address: $IP_ADDRESS"

# Add another repository &  Update the system
sudo dnf install -y epel-release && dnf update

# Install necessary packages: wget, curl, fapolicyd and others
sudo dnf install -y wget curl fapolicyd htop

# Set hostname
HOSTNAME="foreman.cacs.devsec"
SHORT_HOSTNAME="foreman"

sudo hostnamectl set-hostname $HOSTNAME
echo $SHORT_HOSTNAME | sudo tee /etc/hostname

# Update /etc/hosts file
# First, backup the hosts file
sudo cp /etc/hosts /etc/hosts.backup

# Remove any existing entries for our hostname
sudo sed -i "/$HOSTNAME/d" /etc/hosts
sudo sed -i "/$SHORT_HOSTNAME/d" /etc/hosts

# Add new entry to /etc/hosts
echo "$IP_ADDRESS $HOSTNAME $SHORT_HOSTNAME" | sudo tee -a /etc/hosts

# Install Puppet 8 Repository
cd /tmp/
sudo dnf -y install https://yum.puppet.com/puppet8-release-el-9.noarch.rpm

# Prompt user to choose between stable and nightly versions
read -p "Do you want to install the stable version of Foreman? [Y/n]: " install_stable

if [[ $install_stable =~ ^[Yy]$ ]]
then
    # Enable the stable Foreman repositories
    sudo dnf -y install https://yum.theforeman.org/releases/3.13/el9/x86_64/foreman-release.rpm
else
    # Enable the nightly Foreman repositories
    sudo dnf -y install https://yum.theforeman.org/releases/nightly/el9/x86_64/foreman-release.rpm
fi

# Install Foreman installer
sudo dnf -y install foreman-installer


# Run the Foreman installer with the options below. You can edit this line and populate as required. Please refer to the Documentation of 3.13
sudo foreman-installer -v \
    --enable-foreman-plugin-proxmox \
    --enable-foreman-plugin-ansible \
    --enable-foreman-plugin-remote-execution \
    --enable-foreman-proxy-plugin-remote-execution-script \
    --enable-foreman-proxy-plugin-ansible

#********************************************************************************************************************
# Enable services after installation.  Uncomment the services you want to enable

# systemctl enable --now fapolicyd



# Print completion message with detected IP
echo "==============================================="
echo "Installation complete!"
echo "Foreman has been installed with IP: $IP_ADDRESS"
echo "You can access the web interface at: https://$HOSTNAME"
echo "Proxmox plugin has been installed and enabled"
echo "Check /var/log/foreman-installer/foreman-installer.log for details"
echo "==============================================="

echo "Next steps:"
echo "1. Log into the Foreman web interface"
echo "2. Navigate to Infrastructure > Compute Resources"
echo "3. Add a new Compute Resource of type Proxmox"
echo "4. Configure your Proxmox connection details:"
echo "   - Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
echo "   - API Token ID"
echo "   - API Token Secret"
echo "==============================================="