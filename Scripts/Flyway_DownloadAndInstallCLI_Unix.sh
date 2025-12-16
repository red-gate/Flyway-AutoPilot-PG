#!/bin/bash

# ===========================
# Script Name: Flyway_DownloadAndInstallCLI.sh
# Version: 1.1.0
# Author: Chris Hawkins (Redgate Software Ltd)
# Last Updated: 2025-12-16
# Description: Install Flyway CLI on Linux with cleanup of old versions and PATH handling
# ===========================

set -e

SCRIPT_VERSION="1.1.0"
echo "Running Flyway Installer Script - Version $SCRIPT_VERSION"

# ---------------------------
# Configurable Variables
# ---------------------------
FLYWAY_VERSION="${FLYWAY_VERSION:-Latest}"          # Default to Latest if not set
FLYWAY_INSTALL_DIR="${FLYWAY_INSTALL_DIR:-/opt/flyway}"  # Default install location
GLOBAL_PATH_UPDATE="${GLOBAL_PATH_UPDATE:-true}"   # Set to false to skip updating /etc/profile

echo "Requested Flyway version: $FLYWAY_VERSION"
echo "Flyway install directory: $FLYWAY_INSTALL_DIR"
echo "Global PATH update: $GLOBAL_PATH_UPDATE"

# ---------------------------
# Helper Functions
# ---------------------------
get_installed_version() {
    if command -v flyway >/dev/null 2>&1; then
        flyway --version | grep -Eo 'Flyway (Community|Pro|Enterprise|Teams) Edition [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $4}'
    else
        echo "none"
    fi
}

get_latest_version_from_website() {
    content=$(curl -s https://documentation.red-gate.com/flyway/reference/usage/command-line)
    echo "$content" | grep -oP 'flyway-commandline-\K\d+\.\d+\.\d+(?=-linux-x64.tar.gz)' | head -n 1
}

cleanup_old_versions() {
    echo "Cleaning up old Flyway versions..."
    for dir in "$FLYWAY_INSTALL_DIR"/flyway-*; do
        # Skip current version and non-existent
        [ -d "$dir" ] || continue
        [[ "$dir" == "$INSTALL_DIR" ]] && continue

        echo "Removing old Flyway version at $dir"
        sudo rm -rf "$dir"
    done
}

# ---------------------------
# Determine Flyway version
# ---------------------------
if [[ "$FLYWAY_VERSION" =~ [Ll]atest ]]; then
    LATEST_VERSION=$(get_latest_version_from_website)
    if [ -z "$LATEST_VERSION" ]; then
        echo "Could not detect latest Flyway version. Exiting."
        exit 1
    fi
    echo "Latest Flyway version detected: $LATEST_VERSION"
    FLYWAY_VERSION="$LATEST_VERSION"
fi

# ---------------------------
# Installation directory
# ---------------------------
INSTALL_DIR="$FLYWAY_INSTALL_DIR/flyway-$FLYWAY_VERSION"

# ---------------------------
# Check if already installed
# ---------------------------
if [ -d "$INSTALL_DIR" ]; then
    echo "Flyway $FLYWAY_VERSION already installed at $INSTALL_DIR. Skipping download."
else
    echo "Downloading and installing Flyway $FLYWAY_VERSION..."
    wget -qO- "https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/$FLYWAY_VERSION/flyway-commandline-$FLYWAY_VERSION-linux-x64.tar.gz" \
        | tar -xvz

    # Ensure parent directory exists
    mkdir -p "$FLYWAY_INSTALL_DIR"

    # Move extracted folder
    mv "flyway-$FLYWAY_VERSION" "$INSTALL_DIR"
fi

# ---------------------------
# Update PATH for current session
# ---------------------------
export PATH="$INSTALL_DIR:$PATH"
echo "PATH updated for current session: $PATH"

# ---------------------------
# Attempt global PATH update (optional)
# ---------------------------
if [ "$GLOBAL_PATH_UPDATE" = "true" ]; then
    if sudo sh -c "echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> /etc/profile"; then
        echo "Global PATH updated in /etc/profile"
    else
        echo "Warning: Could not update global PATH, continuing..."
    fi
fi

# ---------------------------
# Cleanup old Flyway versions
# ---------------------------
cleanup_old_versions

# ---------------------------
# Verify installation
# ---------------------------
if flyway --version >/dev/null 2>&1; then
    echo "Flyway $FLYWAY_VERSION installed successfully and running."
else
    echo "Flyway installation failed!"
    exit 1
fi
