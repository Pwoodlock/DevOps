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

# Function to check command success
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed"
        exit 1
    fi
}

# Get the IP address
IP_ADDRESS=$(get_primary_ip)

# Verify we got an IP address
if [ -z "$IP_ADDRESS" ]; then
    echo "ERROR: Could not determine IP address"
    exit 1
fi

echo "Detected IP address: $IP_ADDRESS"

# Update the system
echo "Updating system packages..."
sudo dnf update -y
check_command "System update"

# Install necessary packages
echo "Installing required packages..."
sudo dnf install -y wget curl fapolicyd
check_command "Package installation"

# Set hostname
HOSTNAME="foremann.cacs.devsec"
SHORT_HOSTNAME="foremann"

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
check_command "Puppet repository installation"

# Prompt user to choose between stable and nightly versions
read -p "Do you want to install the stable version of Foreman? [Y/n]: " install_stable

if [[ $install_stable =~ ^[Yy]$ ]]
then
    echo "Installing stable version..."
    sudo dnf -y install https://yum.theforeman.org/releases/3.13/el9/x86_64/foreman-release.rpm
else
    echo "Installing nightly version..."
    sudo dnf -y install https://yum.theforeman.org/releases/nightly/el9/x86_64/foreman-release.rpm
fi
check_command "Foreman repository installation"

# Install Foreman installer
echo "Installing Foreman..."
sudo dnf -y install foreman-installer
check_command "Foreman installer installation"

# Run the Foreman installer
echo "Configuring Foreman..."
sudo foreman-installer -v \
    --enable-foreman-plugin-proxmox \
    --enable-foreman-plugin-ansible \
    --enable-foreman-plugin-remote-execution \
    --enable-foreman-proxy-plugin-remote-execution-script
check_command "Foreman configuration"

# Enable fapolicyd
sudo systemctl enable --now fapolicyd
check_command "fapolicyd service activation"

# Initialize monitoring status message
MONITORING_MSG="Monitoring was not configured. You can set it up later by following the documentation."

# Prompt user for monitoring setup
read -p "Would you like to configure metrics collection for external Grafana monitoring? [Y/n]: " setup_monitoring

if [[ $setup_monitoring =~ ^[Yy]$ ]]
then
    echo "Setting up metrics collection for external Grafana monitoring..."
    
    # Install PCP and required monitoring packages
    sudo dnf install -y pcp \
        pcp-pmda-apache \
        pcp-pmda-openmetrics \
        pcp-pmda-postgresql \
        pcp-pmda-redis \
        pcp-system-tools \
        foreman-pcp
    check_command "PCP packages installation"

    # Enable and start PCP daemons
    sudo systemctl enable --now pmcd pmlogger
    check_command "PCP services activation"

    # Configure PCP data collection
    sudo ln -s /etc/pcp/proc/foreman-hotproc.conf /var/lib/pcp/pmdas/proc/hotproc.conf
    
    # Install and configure monitoring components
    (cd /var/lib/pcp/pmdas/proc && sudo ./Install)
    check_command "Process monitoring PMDA installation"
    
    sudo foreman-installer --enable-apache-mod-status
    (cd /var/lib/pcp/pmdas/apache && sudo ./Install)
    check_command "Apache monitoring configuration"
    
    (cd /var/lib/pcp/pmdas/postgresql && sudo ./Install)
    check_command "PostgreSQL monitoring configuration"

    # Enable Foreman telemetry
    sudo foreman-installer --foreman-telemetry-prometheus-enabled true
    check_command "Foreman telemetry configuration"

    # Configure PCP for Foreman metrics
    cd /var/lib/pcp/pmdas/openmetrics
    echo "https://$(hostname)/metrics" > config.d/foreman.url
    sudo ./Install
    check_command "PCP metrics configuration"

    # Enable remote access
    sudo systemctl enable --now pmproxy
    check_command "PCP proxy service activation"

    # Configure firewall
    sudo firewall-cmd --permanent --add-port=44322/tcp
    sudo firewall-cmd --reload
    check_command "Firewall configuration"

    MONITORING_MSG="
Monitoring Configuration:
- PCP metrics available on port 44322
- Use this server's IP/hostname ($IP_ADDRESS) when configuring external Grafana
- Ensure your external Grafana instance can reach port 44322 on this server"
fi

# Print final completion message with all information
echo "==============================================="
echo "Foreman Installation Complete!"
echo "-----------------------------------------------"
echo "Core Installation:"
echo "- Foreman URL: https://$HOSTNAME"
echo "- Server IP: $IP_ADDRESS"
echo "- Installed plugins: Proxmox, Ansible, Remote Execution"
echo "- Log file: /var/log/foreman-installer/foreman-installer.log"
echo "-----------------------------------------------"
echo -e "$MONITORING_MSG"
echo "-----------------------------------------------"
echo "Next Steps:"
echo "1. Log into the Foreman web interface"
echo "2. Navigate to Infrastructure > Compute Resources"
echo "3. Add a new Compute Resource of type Proxmox:"
echo "   - Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
echo "   - API Token ID"
echo "   - API Token Secret"
if [[ $setup_monitoring =~ ^[Yy]$ ]]; then
echo "4. Set up your external Grafana instance to connect to this server"
fi
echo "==============================================="