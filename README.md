# Lilypad Local Stack

This guide should help with the set up of a Lilypad development environment on supported GPU cloud providers. The aim is to assist with module building where hardware requirements exceed local capabilities.

## Lambda.ai

### SSH Key

Create a new key pair in the Lambda console and download the `.pem` file.

### Create Instance

Launch GPU instance on Lambda (https://lambda.ai/)
- Select instance, e.g. 1x A6000 (48GB GPU)
- Select region
- Don't attach a filesystem
- Select your SSH key

Copy the instance IP address after the deployment is complete.

### Instance Configuration

Logon to the instance using SSH. The default username is `ubuntu`.

```bash
ssh -i lambda.pem ubuntu@<ip-address>
```

You can choose between a local Lilypad development environment with or without a local Docker registry.

#### With local Docker registry
This option allows you to host your own Docker images for module building purposes. You can use the `lilypad-local-stack.sh` setup to include the registry in the setup.

```
wget https://raw.githubusercontent.com/rhochmayr/lilypad-local-stack/main/lilypad-local-stack.sh
chmod +x lilypad-local-stack.sh
./lilypad-local-stack.sh
```

#### Without local Docker registry
This option is suitable for general testing and development purposes. You can use the `lilypad-local-stack-no-registry.sh` setup to build and run modules on your instance. Images can be pushed and pulled from the Docker Hub or any other public registry.

```
wget https://raw.githubusercontent.com/rhochmayr/lilypad-local-stack/main/lilypad-local-stack-no-registry.sh
chmod +x lilypad-local-stack-no-registry.sh
./lilypad-local-stack-no-registry.sh
```

### Reboot

```
sudo reboot
```

### Setup Dev Environment

After the reboot login again und complete the setup with the following commands:

```
cd lilypad/
./stack compose-build
./stack compose-init
./stack compose-services #(Press Ctrl+C to stop)
./stack compose-up
```

### Local registry
If you have set up a local registry, you can build, push and pull your images to the local registry using the following command:

```
docker build -t registry.local/<module-name>:<tag> .
docker push registry.local/<module-name>:<tag>
```

### Setup Summary

- Sets Go and Node.js versions, and profile file for environment variables.
- Adds current user to the Docker group.
- Installs btop (system monitor) and yq (YAML processor).
- Installs Go (Golang) and updates shell profile with Go environment variables.
- Installs Node.js using NVM (Node Version Manager).
- Clones the Lilypad GitHub repository.
- Updates docker-compose YAML files for GPU support and solver environment variables.
- Generates a self-signed SSL certificate for a local Docker registry.
- Adds the registry domain to /etc/hosts.
- Copies the certificate into the Docker build context.
- Patches the Bacalhau Dockerfile to trust the self-signed certificate.
- Adds the registry as an extra host in docker-compose.
- Restarts the Docker service.
- Sets up and runs a local Docker registry with TLS.
- Generates random PostgreSQL credentials and updates them in docker-compose and stack files.
- Prints instructions to reboot and run Lilypad stack commands after reboot.

### Notes

General notes:

- Expected time to set up the instance is around 10 minutes.

Things to consider:

- Bacalhau and Resource Provider compose files needed to be patched to support GPU and the local registry. Maybe nvidia runtime just needs to be configured as default?
- Unsure if local registry is really needed. Idea was to not have to push/pull very large images (e.g. 50GB+) multiple times to/from Docker Hub during module development. Might not be an issue as bandwidth on Lamdba instances are very high and the local registry doesn't seem to be much faster than Docker Hub.
- Random PostgreSQL credentials are generated because the instance was infected with a crypto miner after 10 minutes when using the default credentials.
