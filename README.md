# Simulator

This project runs a Go-based simulator which interacts with a Kubernetes cluster via a `broker` submodule.

## Prerequisites

1.  **Go:** Version 1.21+ installed.
2.  **Kubernetes Cluster:** A running Kubernetes cluster (e.g., Minikube, Docker Desktop Kubernetes).
3.  **`kubectl`:** Installed and configured for your cluster.
4.  **Git:** Installed.
5.  **(For `.sh` scripts on Windows):** Shell environment like Git Bash or WSL.

## Setup

1.  **Initialize Submodules:**
    ```bash
    git submodule update --init --recursive
    ```
2.  **Install Go Dependencies:**
    ```bash
    go mod tidy
    ```

## Running the Simulator

### Using PowerShell (Windows)

1.  **Navigate to project directory.**
2.  **Start:** `.\start_simulator.ps1`
3.  **Stop & Clean K8s Resources:** `.\stop_simulator.ps1`
    *(Note: If script execution is blocked, run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` once in an elevated PowerShell.)*

### Using Shell (Git Bash, WSL, Linux, macOS)

1.  **Navigate to project directory.**
2.  **Make scripts executable (one-time):**
    ```bash
    chmod +x start_simulator.sh
    chmod +x stop_simulator.sh
    ```
3.  **Start:** `./start_simulator.sh`
4.  **Stop & Clean K8s Resources:** `./stop_simulator.sh`

