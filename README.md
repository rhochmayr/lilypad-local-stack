# lilypad-local-stack

This guide should help with the set up of a Lilypad development environment on supported GPU cloud providers, to help with module building where hardware requirements exceed local capabilities.

## Lambda.ai

### SSH Key

Create a new key pair in the Lambda console and download the `.pem` file.

### Create Instance

Launch GPU instance on Lambda (https://lambda.ai/)
- Select instance 1x A6000 (48GB GPU)
- Select region
- Don't attach a filesystem
- Select your SSH key

Copy the instance IP address after the deployment is complete.

### Instance Configuration

Logon to the instance using SSH. The default username is `ubuntu`.

```bash
ssh -i lambda.pem ubuntu@<ip-address>
```

You can choose between a local Lilypad development environment with or without a private Docker registry.

#### With local Docker registry
This option allows you to host your own Docker images for module building purposes. You can use the `lilypad-local-stack.sh` setup to include the registry in the setup.

```
wget https://raw.githubusercontent.com/rhochmayr/lilypad-local-stack/main/lilypad-local-stack.sh
chmod +x lilypad-local-stack.sh
./lilypad-local-stack.sh
```

#### Without local Docker registry
This option is suitable for testing and development purposes. You can use the `lilypad-local-stack-no-registry.sh` setup to build and run images locally on your instance. Images can be pushed and pulled from the Docker Hub or any other public registry.

```
wget https://raw.githubusercontent.com/rhochmayr/lilypad-local-stack/main/lilypad-local-stack.sh
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