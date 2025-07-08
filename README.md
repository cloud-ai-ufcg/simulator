# Simulator Project

This project provides a simulator environment using Docker containers for an Actuator, a Broker, a Monitor, and an AI-Engine, along with helper scripts for Kubernetes infrastructure.
It also works with submodules to manage dependencies, such as the Broker, Actuator, Monitor, and AI-Engine repositories.

After cloning the repository, you need to initialize the submodules using the following command:
```sh
make init-submodules
```
or
```sh
git submodule update --init --recursive
```

## Requirements

- Docker
- Go
- (Optional) Kubernetes and kubectl
- (Optional) WSL for Windows users

## Main Makefile Targets

- **all / setup-and-start**  
  Sets up the Kubernetes infrastructure, starts the Broker, Actuator, Monitor, and AI-Engine containers, and then runs the Go simulator. This is the main target to get everything running from scratch.
  ```sh
  make
  # or
  make setup-and-start
  ```

- **start**  
  Runs only the Go simulator. This assumes that the Kubernetes infrastructure and all required containers are already running.
  ```sh
  make start
  ```

- **run-all-containers**  
  Starts all required containers (Broker, Actuator, Monitor, AI-Engine) without running the Go simulator.
  ```sh
  make run-all-containers
  ```

- **stop-all-containers**  
  Stops and removes all simulator containers.
  ```sh
  make stop-all-containers
  ```

- **setup-kubernetes-infra**  
  Runs the script to set up the Kubernetes infrastructure.
  ```sh
  make setup-kubernetes-infra
  ```

- **Individual Container Start Targets**
  - `make start-broker-container`
  - `make start-actuator-container`
  - `make start-monitor-container`
  - `make start-ai-engine-container`

- **help**  
  Shows a list of available targets and their descriptions.
  ```sh
  make help
  ```

## Container Details

- **Actuator**
  - Image: `actuator-api`
  - Container name: `actuator-simulator`
  - Dockerfile: `actuator/Dockerfile.api`
  - Listens on port: 8085

- **Broker**
  - Image: `broker:latest`
  - Container name: `broker-simulator`
  - Dockerfile: `broker/Dockerfile.api`
  - Listens on port: 8080

- **Monitor**
  - Image: `monitor:latest`
  - Container name: `monitor-simulator`
  - Dockerfile: `monitor/Dockerfile`
  - Network: `host`

- **AI-Engine**
  - Image: `ai-engine-api`
  - Container name: `ai-engine-simulator`
  - Dockerfile: `ai-engine/Dockerfile.api`
  - Listens on port: 8083

## Notes

- The Makefile automatically builds images if they do not exist.
- Kubeconfig and other necessary files are mounted into the containers as needed.
- For WSL users, the Makefile attempts to detect and use the correct Windows home directory for Go commands.

---
