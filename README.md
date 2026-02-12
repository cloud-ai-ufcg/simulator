# WASP -- Workload Agent-Based Simulation Platform

WASP is a modular research platform for studying AI-driven workload
migration strategies in hybrid Kubernetes environments. It integrates
simulation, monitoring, reasoning, and execution components into a
reproducible, containerized environment suitable for experimentation,
demonstration, and academic evaluation.

------------------------------------------------------------------------

## Overview

WASP provides:

-   Multi-cluster Kubernetes simulation
-   Telemetry-driven migration recommendations
-   AI-agnostic reasoning capabilities
-   Human-in-the-loop (HIL) validation
-   Fully automated execution mode
-   Reproducible experimental runs

WASP is a reproducible experimental platform for evaluating AI-driven workload migration strategies under controlled multi-cluster Kubernetes simulations.

------------------------------------------------------------------------

## Architecture

WASP consists of the following services:

-   **Simulator** -- Orchestrates execution and event scheduling
-   **Broker** -- Dispatches workload and infrastructure events
-   **Monitor** -- Collects periodic telemetry snapshots
-   **AI Engine** -- Generates structured migration recommendations
-   **Actuator** -- Validates and applies approved recommendations
-   **Operator Interface (optional)** -- Enables human review

All components are containerized and orchestrated via Docker.

------------------------------------------------------------------------

## Requirements

Minimum requirements:

-   Docker (with Docker Compose support)
-   GNU Make
-   Go (for running the simulator locally)

No pre-installed Kubernetes cluster is required. The KWOK +
Karmada-based infrastructure is provisioned automatically.

------------------------------------------------------------------------

## Quick Start

### Submodules Initialization

WASP relies on Git submodules for its core services (Broker, Monitor, Actuator, AI Engine, etc.).  
After cloning the repository, you **must initialize and update all submodules** before running the system.

First, clone the repository 
then, from the root folder (/simulator/) run:

```
git submodule update --init --recursive
```

The Operator Interface (HIL mode) will be available at:

## LLM Provider Configuration (Required)

WASP's default configuration uses **OpenRouter** as the LLM abstraction
layer.\
Before running the simulator, you **must configure an OpenRouter API
key** inside the AI Engine.

## Steps

1.  Create an account at:\
    https://openrouter.ai

2.  Generate an API key.

3.  Navigate to the `ai-engine/` directory and create a `.env` file:

``` bash
cd ai-engine
touch .env
```

4.  Add your key to the file:

``` bash
OPENROUTER_API_KEY=your_api_key_here
```

Alternatively, you may export it directly in your shell:

``` bash
export OPENROUTER_API_KEY=your_api_key_here
```

------------------------------------------------------------------------

Without a valid OpenRouter API key, the AI Engine will not be able to
generate migration recommendations and the default simulation will fail.


### Human-in-the-Loop Mode (Recommended)

    make

This command:

1.  Cleans previous infrastructure and containers
2.  Provisions federated Kubernetes clusters
3.  Starts all required services
4.  Cleans MongoDB state
5.  Launches the simulator

Alternatively, the commands below executes the steps above sequentially:

```
make setup-kubernetes-infra
make run-all-containers
make start
```

The Operator Interface (HIL mode) will be available at:

    http://localhost:5173

------------------------------------------------------------------------

### Fully Automated Mode

    make setup-and-start-auto

In this mode, migration recommendations are automatically approved and
applied.

------------------------------------------------------------------------

## Execution Workflow

A typical run proceeds as follows:

1.  Infrastructure provisioning (two federated clusters).
2.  Workload injection via the Broker.
3.  Telemetry collection every 30 seconds.
4.  AI reasoning every 60 seconds.
5.  Recommendation validation (HIL or Auto).
6.  Migration execution via the Actuator.
7.  Logs and metrics persisted for analysis.

------------------------------------------------------------------------

## Output Structure

Each simulation run generates a timestamped directory containing:

-   metrics.json
-   logs/ (actuator, broker, monitor, ai-engine logs)

These artifacts enable reproducibility and post-run evaluation.

------------------------------------------------------------------------

## Makefile Targets

Full setup + run (HIL):

    make

Full setup + run (Auto):

    make setup-and-start-auto

Setup infrastructure only:

    make setup

Start containers (HIL):

    make run-all-containers

Start containers (Auto):

    make run-all-containers-auto

Stop all containers:

    make stop-all-containers

Restart services cleanly:

    make restart-all-containers

------------------------------------------------------------------------

## Research Focus

WASP emphasizes:

-   Clear separation between monitoring, reasoning, validation, and
    execution
-   Model-agnostic AI integration
-   Controlled experimentation through simulation
-   Operator oversight and auditability
-   Reproducible research workflows

------------------------------------------------------------------------

## Licenses

This project is intended for academic and research use.
