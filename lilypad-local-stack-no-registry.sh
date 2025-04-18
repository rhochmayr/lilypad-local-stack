#!/bin/bash
# filepath: f:\lp-scripts\lilypad-setup.sh

set -e

# --- CONFIGURATION ---
GO_VERSION="1.23.2"
NODE_VERSION="20"
PROFILE_FILE="$HOME/.bashrc"  # Change to .zshrc if using Zsh

# --- SYSTEM UPDATE ---
#echo "Updating system..."
#sudo apt update && sudo apt upgrade -y

# --- DOCKER GROUP ---
echo "Adding user to docker group..."
sudo adduser "$(id -un)" docker || true

# --- BTOP INSTALL ---
echo "Installing btop..."
sudo apt install -y btop

# --- YQ INSTALL ---
echo "Installing yq..."
sudo wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
sudo chmod +x /usr/bin/yq

# --- GOLANG INSTALL ---
echo "Installing Go $GO_VERSION..."
GO_TAR="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TAR}"
wget -q $GO_URL
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf $GO_TAR
rm $GO_TAR

if ! grep -q "export GOROOT=/usr/local/go" $PROFILE_FILE; then
  echo -e "\n# Go environment setup" >> $PROFILE_FILE
  echo "export GOROOT=/usr/local/go" >> $PROFILE_FILE
  echo "export GOPATH=\$HOME/go" >> $PROFILE_FILE
  echo "export PATH=\$GOPATH/bin:\$GOROOT/bin:\$PATH" >> $PROFILE_FILE
  echo "Go paths added to $PROFILE_FILE"
else
  echo "Go paths already set in $PROFILE_FILE"
fi

# Set Go env for current script session
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

echo "Go installation complete:"
go version || echo "Go not found in PATH"
echo "GOROOT: $GOROOT"
echo "GOPATH: $GOPATH"

# --- NODE/NVM INSTALL ---
echo "Installing Node.js via NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install $NODE_VERSION
node -v
nvm current
npm -v

# --- CLONE LILYPAD REPO ---
echo "Cloning Lilypad repo..."
git clone https://github.com/Lilypad-Tech/lilypad.git || true

# --- UPDATE DOCKER COMPOSE FILES ---
echo "Updating docker-compose.base.yml for GPU support..."
yq -i '
    .services.bacalhau.deploy.resources.reservations.devices = [
        {
            "driver": "nvidia",
            "count": 1,
            "capabilities": ["gpu"]
        }
    ]
' lilypad/docker/docker-compose.base.yml
echo "docker-compose.base.yml updated."

echo "Updating docker-compose.dev.yml for solver and GPU support..."
yq -i '
    .services.solver.environment += [
        "SERVER_VALIDATION_TOKEN_SECRET=912dd001a6613632c066ca10a19254430db2986a84612882a18f838a6360880e",
        "SERVER_VALIDATION_TOKEN_KID=key-dev"
    ]
' lilypad/docker/docker-compose.dev.yml

yq -i '
    .services["resource-provider"].deploy.resources.reservations.devices = [
        {
            "driver": "nvidia",
            "count": 1,
            "capabilities": ["gpu"]
        }
    ]
' lilypad/docker/docker-compose.dev.yml

yq -i '
.services["resource-provider"].build.args |=
    ([.[] | select(. != "COMPUTE_MODE=cpu" and . != "COMPUTE_MODE=gpu")] + ["COMPUTE_MODE=gpu"])
' lilypad/docker/docker-compose.dev.yml

echo "docker-compose.dev.yml updated."

# --- UPDATE POSTGRES USER AND PASSWORD ---
echo "Generate random postgres credentials"
NEW_USER="user_$(openssl rand -hex 4)"
NEW_PASS="pass_$(openssl rand -hex 8)"

echo "🔐 New PostgreSQL credentials:"
echo "User: $NEW_USER"
echo "Pass: $NEW_PASS"

echo "Update docker-compose.base.yml"
sed -i -E "s|(- POSTGRES_USER=).*|\1$NEW_USER|" lilypad/docker/docker-compose.base.yml
sed -i -E "s|(- POSTGRES_PASSWORD=).*|\1$NEW_PASS|" lilypad/docker/docker-compose.base.yml

echo "Update STORE_CONN_STR in stack file"
sed -i -E "s|(STORE_CONN_STR=postgres://)[^:]+:[^@]+@\S+|\1$NEW_USER:$NEW_PASS@localhost:5432/solver-db?sslmode=disable|" lilypad/stack

echo "✅ Credentials updated in docker-compose.base.yml and stack script."

# --- FINISHED ---
echo "Setup complete! Please reboot your system to apply all changes."
echo "After reboot, run the following commands in the lilypad directory:"
echo "  cd lilypad"
echo "  ./stack compose-build"
echo "  ./stack compose-init"
echo "  ./stack compose-up"