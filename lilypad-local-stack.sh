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

# --- LOCAL CERTIFICATE ---
echo "Setting variables for local certificate generation"
CERT_DIR="certs"
CERT_DAYS=365
REGISTRY_NAME="registry"
REGISTRY_PORT=443
CN="registry.local"  # Get the first non-loopback IP

# Remove existing certs directory if it exists
rm -rf "$CERT_DIR"  
rm -rf "openssl-san.cnf" 
rm -rf "lilypad/certs/" 

echo "Using: $CN for certificate Common Name and SAN."

echo "Generate OpenSSL Config"
cat > openssl-san.cnf <<EOF
[req]
default_bits       = 4096
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[dn]
CN = $CN

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CN
EOF

echo "Generating self-signed certificate for local registry..."
mkdir -p "$CERT_DIR"
openssl req -x509 -nodes -days "$CERT_DAYS" \
  -newkey rsa:4096 \
  -keyout "$CERT_DIR/domain.key" \
  -out "$CERT_DIR/domain.crt" \
  -config openssl-san.cnf \
  -extensions req_ext

echo "Trusting self-signed certificate..."
sudo cp "$CERT_DIR/domain.crt" /usr/local/share/ca-certificates/registry.crt
sudo update-ca-certificates

# --- /ETC/HOSTS ---
echo "Adding registry to /etc/hosts..."
echo "127.0.0.1 $CN" | sudo tee -a /etc/hosts

# --- COPY CERT INTO BUILD CONTEXT ---
echo "Copying registry cert into Docker build context..."
mkdir -p lilypad/certs
cp "$CERT_DIR/domain.crt" lilypad/certs/domain.crt
echo "✅ Copied to lilypad/certs/domain.crt"

# --- PATCH BACALHAU DOCKERFILE TO TRUST CERT ---
echo "Patching Bacalhau Dockerfile to trust the self-signed registry cert..."
DOCKERFILE_PATH="lilypad/docker/bacalhau/Dockerfile"

if grep -q "registry.crt" "$DOCKERFILE_PATH"; then
  echo "✔️ Bacalhau Dockerfile already contains cert trust logic. Skipping patch."
else
  PATCHED_FILE="${DOCKERFILE_PATH}.patched"
  patched=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    echo "$line" >> "$PATCHED_FILE"

    # Inject cert trust logic after apt clean
    if [[ $patched -eq 0 && "$line" =~ apt\ clean ]]; then
      echo "" >> "$PATCHED_FILE"
      echo "# Add custom registry certificate and trust it" >> "$PATCHED_FILE"
      echo "COPY certs/domain.crt /usr/local/share/ca-certificates/registry.crt" >> "$PATCHED_FILE"
      echo "RUN update-ca-certificates" >> "$PATCHED_FILE"
      patched=1
    fi
  done < "$DOCKERFILE_PATH"

  mv "$PATCHED_FILE" "$DOCKERFILE_PATH"
  echo "✅ Bacalhau Dockerfile successfully patched."
fi

# --- PATCH DOCKER-COMPOSE FILE FOR EXTRA HOSTS ---
echo "Adding registry to docker-compose base file..."
HOST_IP=$(hostname -I | awk '{print $1}')
yq -i "
  .services.bacalhau.extra_hosts += [\"$CN:$HOST_IP\"]
" lilypad/docker/docker-compose.base.yml
echo "✅ Added registry to docker-compose base file."

# --- DOCKER SERVICE ---
echo "Restarting Docker service..."
sudo systemctl restart docker

# --- DOCKER REGISTRY ---
echo "Setting up local Docker registry..."
echo "Removing existing registry container..."
sudo docker rm -f "$REGISTRY_NAME" 2>/dev/null || true

echo "Running Docker registry..."
sudo docker run -d \
  --restart=always \
  --name "$REGISTRY_NAME" \
  -v "$(pwd)/$CERT_DIR:/certs" \
  -v /var/lib/docker/registry:/var/lib/registry \
  -e REGISTRY_HTTP_ADDR=0.0.0.0:$REGISTRY_PORT \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  -p $REGISTRY_PORT:443 \
  registry:3

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