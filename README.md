# Simulator Project

This project provides a simulator environment using Docker containers for both an Actuator and a Broker, along with helper scripts for Kubernetes infrastructure and AI-Engine dependencies.

## Requirements

- Docker
- Python 3 and pip
- (Optional) Kubernetes and kubectl
- (Optional) WSL for Windows users

## Main Makefile Targets

- **all / setup-and-start**  
  Sets up the Kubernetes infrastructure, installs AI-Engine dependencies, starts the Broker and Actuator containers, and runs the Go simulator.
  ```sh
  make
  # or
  make setup-and-start
  ```

- **start-broker-container**  
  Builds (if needed) and starts the Broker container (`broker-simulator`).
  ```sh
  make start-broker-container
  ```

- **start-actuator-container**  
  Builds (if needed) and starts the Actuator container (`actuator-simulator`).
  ```sh
  make start-actuator-container
  ```

- **start**  
  Runs only the Go simulator (assumes infrastructure and containers are already running).
  ```sh
  make start
  ```

- **setup-kubernetes-infra**  
  Runs the script to set up Kubernetes infrastructure.
  ```sh
  make setup-kubernetes-infra
  ```

- **install-ai-deps**  
  Installs Python dependencies for the AI-Engine.
  ```sh
  make install-ai-deps
  ```

- **stop-all-containers**  
  Stops and removes both the Actuator and Broker containers.
  ```sh
  make stop-all-containers
  ```

- **help**  
  Shows a list of available targets.
  ```sh
  make help
  ```

## Container Details

- **Actuator**
  - Image: `actuator-api`
  - Container name: `actuator-simulator`
  - Dockerfile: `actuator/Dockerfile.api`
  - Exposes port: 8085

- **Broker**
  - Image: `broker:latest`
  - Container name: `broker-simulator`
  - Dockerfile: `broker/Dockerfile.api`
  - Exposes port: 8080

## Notes

- The Makefile automatically builds images if they do not exist.
- Kubeconfig and other necessary files are mounted into the containers as needed.
- For WSL users, the Makefile attempts to detect and use the correct Windows home directory for Go and Python commands.

---
