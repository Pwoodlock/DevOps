#!/bin/bash

# Foreman Monitoring Setup Script
# This script installs and configures PCP monitoring for Foreman
# Based on Foreman community recommendations

# Exit on any error
set -e

# Function to check available disk space
check_disk_space() {
    local required_space=20
    local available_space=$(df -BG /var/log/pcp | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$available_space" -lt "$required_space" ]; then
        echo "ERROR: Insufficient disk space. Required: ${required_space}GB, Available: ${available_space}GB"
        exit 1
    fi
}

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to verify service status
verify_service() {
    if systemctl is-active --quiet "$1"; then
        log_message "$1 is running"
        return 0
    else
        log_message "ERROR: $1 is not running"
        return 1
    fi
}

# Function to backup configuration files
backup_config() {
    local file=$1
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d)"
        log_message "Backed up $file"
    fi
}

# Main installation
log_message "Starting Foreman monitoring installation"

# Check disk space
log_message "Checking disk space requirements..."
check_disk_space

# Install PCP and required packages
log_message "Installing PCP packages..."
dnf install -y pcp \
    pcp-pmda-apache \
    pcp-pmda-openmetrics \
    pcp-pmda-postgresql \
    pcp-pmda-redis \
    pcp-system-tools \
    foreman-pcp

# Enable and start PCP services
log_message "Enabling and starting PCP services..."
systemctl enable --now pmcd pmlogger

# Configure process monitoring
log_message "Configuring process monitoring..."
ln -sf /etc/pcp/proc/foreman-hotproc.conf /var/lib/pcp/pmdas/proc/hotproc.conf
cd /var/lib/pcp/pmdas/proc
./Install </dev/null

# Configure Apache monitoring
log_message "Configuring Apache monitoring..."
foreman-installer --enable-apache-mod-status
cd /var/lib/pcp/pmdas/apache
./Install </dev/null

# Configure PostgreSQL monitoring
log_message "Configuring PostgreSQL monitoring..."
cd /var/lib/pcp/pmdas/postgresql
./Install </dev/null

# Enable Foreman telemetry
log_message "Enabling Foreman telemetry..."
foreman-installer --foreman-telemetry-prometheus-enabled true

# Configure OpenMetrics PMDA for Foreman
log_message "Configuring OpenMetrics PMDA..."
cd /var/lib/pcp/pmdas/openmetrics
FOREMAN_FQDN=$(hostname -f)
echo "https://${FOREMAN_FQDN}/metrics" > config.d/foreman.url
./Install </dev/null

# Restart PCP services
log_message "Restarting PCP services..."
systemctl restart pmcd pmlogger pmproxy

# Optional: Install Grafana
read -p "Would you like to install Grafana for web UI access? (y/n) " install_grafana
if [[ $install_grafana =~ ^[Yy]$ ]]; then
    log_message "Installing Grafana..."
    dnf install -y grafana grafana-pcp
    
    systemctl enable --now pmproxy grafana-server
    
    # Configure firewall
    firewall-cmd --permanent --add-service=grafana
    firewall-cmd --reload
    
    log_message "Grafana installed and configured on port 3000"
fi

# Verify installation
log_message "Verifying installation..."
pcp

# All services should be running
verify_service pmcd
verify_service pmlogger
[ "$install_grafana" = "y" ] && verify_service grafana-server

# Print completion message
log_message "Installation complete!"
echo "
Monitoring Setup Complete!
=========================
- PCP is configured and running
- Metrics are being collected for:
  * System resources
  * Foreman processes
  * Apache
  * PostgreSQL
  * Redis
"

if [[ $install_grafana =~ ^[Yy]$ ]]; then
    echo "Grafana is available at: http://${FOREMAN_FQDN}:3000
Default credentials:
- Username: admin
- Password: admin (change on first login)
"
fi

echo "
To view metrics, you can use:
- 'pminfo' to list all available metrics
- 'pmval' to view specific metrics
- 'pmstat' to view system performance summary
"