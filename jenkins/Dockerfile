# Start from the official Jenkins SSH agent image
FROM jenkins/ssh-agent:latest

# Switch to root user to install packages and for the final runtime
USER root

# Update package lists and install necessary tools
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    python3 \
    python3-pip \
    openssh-server

# Clean up the apt cache to reduce image size
RUN rm -rf /var/lib/apt/lists/*

# Ensure the setup-sshd script is executable
RUN chmod +x /usr/local/bin/setup-sshd

# Set the entrypoint to the setup-sshd script
ENTRYPOINT ["/usr/local/bin/setup-sshd"]

# Keep the container running
CMD ["tail", "-f", "/dev/null"]