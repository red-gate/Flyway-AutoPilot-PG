#!/bin/bash

# ===========================
# Script Name: Flyway_DownloadAndInstallCLI.sh
# Version: 1.2.0
# Author: Chris Hawkins (Redgate Software Ltd)
# Last Updated: 2025-12-19
# Description: Install Flyway CLI on Linux with cleanup of old versions and PATH handling
#              Supports both manual execution and CI/CD pipelines (GitHub Actions, etc.)
# ===========================

set -e

SCRIPT_VERSION="1.2.0"
echo "Running Flyway Installer Script - Version $SCRIPT_VERSION"

# ---------------------------
# Detect execution context
# ---------------------------
# Check if running in CI/CD environment
if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ] || [ -n "$GITLAB_CI" ] || [ -n "$CIRCLECI" ]; then
    IS_CI=true
    echo "CI/CD environment detected"
else
    IS_CI=false
fi

# Check if we have sudo/root access
if [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null; then
    HAS_SUDO=true
else
    HAS_SUDO=false
    echo "No sudo access detected - using user-space installation"
fi

# ---------------------------
# Configurable Variables
# ---------------------------
FLYWAY_VERSION="${FLYWAY_VERSION:-Latest}"          # Default to Latest if not set

# Smart default: use user home if no sudo or in CI, otherwise /opt/flyway
if [ -z "$FLYWAY_INSTALL_DIR" ]; then
    if [ "$HAS_SUDO" = true ] && [ "$IS_CI" = false ]; then
        FLYWAY_INSTALL_DIR="/opt/flyway"
    else
        FLYWAY_INSTALL_DIR="$HOME/.flyway"
    fi
fi

# For CI/CD or non-sudo environments, update user profile instead of system-wide
if [ -z "$GLOBAL_PATH_UPDATE" ]; then
    if [ "$HAS_SUDO" = true ] && [ "$IS_CI" = false ]; then
        GLOBAL_PATH_UPDATE=true
    else
        GLOBAL_PATH_UPDATE=false
    fi
fi

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
        if [ "$HAS_SUDO" = true ] && [[ "$dir" == /opt/* ]]; then
            sudo rm -rf "$dir"
        else
            rm -rf "$dir"
        fi
    done
}

cleanup_old_path_entries() {
    echo "Cleaning up old PATH entries..."
    
    if [ "$GLOBAL_PATH_UPDATE" = true ]; then
        # Clean up /etc/profile
        if [ -f /etc/profile ]; then
            # Create temp file without any flyway PATH entries
            sudo grep -v 'export PATH=.*flyway-' /etc/profile > /tmp/profile.tmp || true
            sudo mv /tmp/profile.tmp /etc/profile
            echo "Removed all old Flyway PATH entries from /etc/profile"
        fi
    else
        # Clean up user profile
        USER_PROFILE=""
        if [ -f "$HOME/.bashrc" ]; then
            USER_PROFILE="$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            USER_PROFILE="$HOME/.bash_profile"
        elif [ -f "$HOME/.profile" ]; then
            USER_PROFILE="$HOME/.profile"
        fi
        
        if [ -n "$USER_PROFILE" ] && [ -f "$USER_PROFILE" ]; then
            # Create temp file without any flyway PATH entries
            grep -v 'export PATH=.*flyway-' "$USER_PROFILE" > "${USER_PROFILE}.tmp" || true
            mv "${USER_PROFILE}.tmp" "$USER_PROFILE"
            echo "Removed all old Flyway PATH entries from $USER_PROFILE"
        fi
    fi
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
    echo "Downloading Flyway $FLYWAY_VERSION from Red Gate..."
    echo "Source: https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/$FLYWAY_VERSION/"
    
    # Use temp directory for extraction to ensure we have write permissions
    TEMP_EXTRACT_DIR=$(mktemp -d)
    cd "$TEMP_EXTRACT_DIR"
    
    wget -qO- "https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/$FLYWAY_VERSION/flyway-commandline-$FLYWAY_VERSION-linux-x64.tar.gz" \
        | tar -xz --no-same-owner
    echo "Download and extraction complete."

    echo "Installing Flyway to $INSTALL_DIR..."
    # Ensure parent directory exists (with or without sudo)
    if [ "$HAS_SUDO" = true ] && [[ "$FLYWAY_INSTALL_DIR" == /opt/* ]]; then
        sudo mkdir -p "$FLYWAY_INSTALL_DIR"
        sudo mv "$TEMP_EXTRACT_DIR/flyway-$FLYWAY_VERSION" "$INSTALL_DIR"
    else
        mkdir -p "$FLYWAY_INSTALL_DIR"
        mv "$TEMP_EXTRACT_DIR/flyway-$FLYWAY_VERSION" "$INSTALL_DIR"
    fi
    
    # Cleanup temp directory
    rm -rf "$TEMP_EXTRACT_DIR"
    cd - >/dev/null
    
    echo "Installation complete."
fi

# ---------------------------
# Update PATH for current session
# ---------------------------
# First, clean up any existing Flyway entries from current PATH to prevent bloat
CLEANED_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "/flyway-" | tr '\n' ':' | sed 's/:$//')

# Now add the new version
export PATH="$INSTALL_DIR:$CLEANED_PATH"
echo "PATH updated for current session (cleaned and updated)"
echo "New PATH: $PATH"

# ---------------------------
# Cleanup old Flyway versions and PATH entries
# ---------------------------
cleanup_old_versions
cleanup_old_path_entries

# ---------------------------
# Add current version to PATH in profile
# ---------------------------
if [ "$GLOBAL_PATH_UPDATE" = true ]; then
    # System-wide update (requires sudo) - add back the current version
    if sudo sh -c "echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> /etc/profile"; then
        echo "Added current Flyway version to /etc/profile"
    else
        echo "Warning: Could not update global PATH, continuing..."
    fi
else
    # User-space update (no sudo required)
    USER_PROFILE=""
    
    # Detect which profile file to use
    if [ -f "$HOME/.bashrc" ]; then
        USER_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        USER_PROFILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.profile" ]; then
        USER_PROFILE="$HOME/.profile"
    else
        USER_PROFILE="$HOME/.profile"
        touch "$USER_PROFILE"
    fi
    
    # Add current version to profile
    echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$USER_PROFILE"
    echo "Added current Flyway version to $USER_PROFILE"
    
    # For CI/CD: also add to GITHUB_PATH if it exists
    if [ -n "$GITHUB_PATH" ]; then
        echo "$INSTALL_DIR" >> "$GITHUB_PATH"
        echo "Added to GITHUB_PATH for GitHub Actions"
    fi
fi

# ---------------------------
# Verify installation
# ---------------------------
if flyway --version >/dev/null 2>&1; then
    echo "Flyway $FLYWAY_VERSION installed successfully and running."
    echo ""
    echo "==========================================="
    echo "IMPORTANT: To use the cleaned PATH in your current terminal:"
    if [ "$GLOBAL_PATH_UPDATE" = true ]; then
        echo "  Run: source /etc/profile"
    else
        if [ -f "$HOME/.bashrc" ]; then
            echo "  Run: source ~/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            echo "  Run: source ~/.bash_profile"
        else
            echo "  Run: source ~/.profile"
        fi
    fi
    echo "Or start a new terminal session."
    echo "==========================================="
else
    echo "Flyway installation failed!"
    exit 1
fi
