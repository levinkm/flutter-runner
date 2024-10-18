#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for yq
if ! command_exists yq; then
    echo "Error: 'yq' is not installed or not in PATH."
    echo "Please install 'yq' before proceeding. You can find installation instructions at:"
    echo "https://github.com/mikefarah/yq#install"
    exit 1
fi

# Check for Flutter
if ! command_exists flutter; then
    echo "Error: 'flutter' is not installed or not in PATH."
    echo "Please install Flutter before proceeding. You can find installation instructions at:"
    echo "https://flutter.dev/docs/get-started/install"
    exit 1
fi

# Define the source and destination paths
SOURCE_SCRIPT="./flutter-runner.sh"
DEST_DIR="/usr/local/bin"
DEST_SCRIPT="$DEST_DIR/flutter-runner"

# Check if the source script exists
if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "Error: $SOURCE_SCRIPT not found in the current directory."
    exit 1
fi

# Check if the script has execute permissions
if [ ! -x "$SOURCE_SCRIPT" ]; then
    echo "Adding execute permissions to $SOURCE_SCRIPT"
    chmod +x "$SOURCE_SCRIPT"
fi

# Copy the script to the destination directory
echo "Installing flutter-runner to $DEST_DIR"
sudo cp "$SOURCE_SCRIPT" "$DEST_SCRIPT"

# Ensure the installed script has execute permissions
sudo chmod +x "$DEST_SCRIPT"

# Verify the installation
if [ -x "$DEST_SCRIPT" ]; then
    echo "Installation successful. You can now use 'flutter-runner' command."
else
    echo "Installation failed. Please check your permissions and try again."
    exit 1
fi

# Install man page if it exists
MAN_PAGE="./flutter-runner.1"
MAN_DIR="/usr/local/share/man/man1"

if [ -f "$MAN_PAGE" ]; then
    echo "Installing man page..."
    sudo mkdir -p "$MAN_DIR"
    sudo cp "$MAN_PAGE" "$MAN_DIR/"
    sudo mandb
    echo "Man page installed. You can now use 'man flutter-runner' to view the documentation."
else
    echo "Man page not found. Skipping man page installation."
fi

echo "Installation complete!"