#!/bin/bash
# Install Go 1.21+ for building mcp-proxy

set -e

GO_VERSION="1.21.5"
INSTALL_DIR="/usr/local"

echo "Installing Go ${GO_VERSION}..."

# Check if Go is already installed
if command -v go &> /dev/null; then
    CURRENT_VERSION=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+')
    echo "Go ${CURRENT_VERSION} is already installed"

    # Check if version is sufficient
    if [[ "$(printf '%s\n' "1.21" "$CURRENT_VERSION" | sort -V | head -n1)" == "1.21" ]]; then
        echo "Go version is sufficient (>= 1.21)"
        exit 0
    else
        echo "Go version too old, upgrading..."
    fi
fi

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        GO_ARCH="amd64"
        ;;
    aarch64)
        GO_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download and install
TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
DOWNLOAD_URL="https://go.dev/dl/${TARBALL}"

echo "Downloading ${DOWNLOAD_URL}..."
cd /tmp
wget -q "${DOWNLOAD_URL}"

echo "Extracting to ${INSTALL_DIR}..."
sudo rm -rf ${INSTALL_DIR}/go
sudo tar -C ${INSTALL_DIR} -xzf "${TARBALL}"
rm "${TARBALL}"

# Add to PATH if not already there
if ! grep -q "export PATH=.*\/go\/bin" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Go installation" >> ~/.bashrc
    echo "export PATH=\$PATH:${INSTALL_DIR}/go/bin" >> ~/.bashrc
    echo "export PATH=\$PATH:\$HOME/go/bin" >> ~/.bashrc
fi

# Also add to current session
export PATH=$PATH:${INSTALL_DIR}/go/bin
export PATH=$PATH:$HOME/go/bin

echo ""
echo "Go ${GO_VERSION} installed successfully!"
echo "Run: source ~/.bashrc  (or start a new terminal)"
echo ""
go version
