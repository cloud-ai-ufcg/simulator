# WASP --- Workload Agent-Based Simulation Platform

**WASP (Workload Agent-Based Simulation Platform)** is a modular
research platform for studying AI-driven workload migration strategies
in hybrid and multi-cluster Kubernetes environments.
It integrates simulation, monitoring, reasoning, validation, and
execution components into a reproducible, containerized environment
designed for:

- Experimentation with AI-assisted workload migration operations
- Reproducible research wrokflows in the area
- Academic experimentation and demonstrations

WASP focuses on **decision-support**, enabling migration recommendations
that can be validated by operators before execution.

------------------------------------------------------------------------

## Overview

WASP provides a controlled experimental environment for evaluating
workload migration strategies under realistic infrastructure
constraints.

### Key Features

-   Multi-cluster Kubernetes simulation (KWOK + Karmada)
-   Telemetry and AI-driven migration recommendations
-   AI-agnostic reasoning engine
-   Human-in-the-Loop (HIL) validation
-   Fully automated execution mode
-   Reproducible experimental runs
-   Containerized microservice architecture

WASP is intended as a **research and evaluation platform**, not a
production orchestration system, as of now.

------------------------------------------------------------------------

## Architecture

WASP implementation is composed of loosely coupled services:
-   **[Simulator](https://github.com/cloud-ai-ufcg/simulator)** --- orchestrates execution timeline and scheduling
-   **[Broker](https://github.com/cloud-ai-ufcg/broker)** --- injects workload and infrastructure events
-   **[Monitor](https://github.com/cloud-ai-ufcg/monitor)** --- collects telemetry snapshots
-   **[AI Engine](https://github.com/cloud-ai-ufcg/ai-engine)** --- generates structured migration recommendations
- **[Recommendations Manager](https://github.com/cloud-ai-ufcg/recommendations-manager)** --- validates and executes approved migrations
  -   **Actuator** --- executes migration actions
  -   **Operator Interface (optional)** --- enables human review before execution

Figure 1 below illustrates how the components interact during execution. The Broker operates independently after it starts, and its behavior is not affected by other components. The Monitor collects telemetry data from Prometheus, which runs in the clusters. At regular intervals, the AI Engine retrieves the latest telemetry data from the Monitor and generates migration recommendations. The Recommendations Manager receives these recommendations and, if not in automated mode, validates them through the Operator Interface. Once approved, the Actuator executes the migration actions.

![WASP Architecture](simulator_images/wasp_architecture.png)
<p align="center"><b>Figure 1:</b> WASP Architecture and component interactions.</p>

------------------------------------------------------------------------

## Requirements
Below are the minimum and recommended specifications your machine should meet to run WASP reliably and without performance issues.

### Hardware

**Minimum:**
-   CPU: 8 cores
-   RAM: 16 GB
-   Disk: 100 GB SSD

**Recommended:**
-   CPU: 12-16 cores
-   RAM: 24-32 GB
-   Disk: 100+ GB NVMe

### Software

Required environment:

-   Ubuntu 22.04.5 LTS
-   GNU Make 4.3
-   Docker 28.3.2
-   Docker Compose 2.36.2 
-   Go 1.24

No preexisting Kubernetes cluster is required. The simulation infrastructure is provisioned automatically.

------------------------------------------------------------------------

## Installation

### 1. Clone Repository and Initialize Submodules

WASP uses Git submodules for its core services, run the following to start them:

``` bash
git clone https://github.com/cloud-ai-ufcg/simulator
cd simulator
git submodule update --init --recursive
```

Failure to initialize submodules will prevent the platform from
starting.

------------------------------------------------------------------------

## LLM Provider Configuration (Required)

The default configuration uses **OpenRouter** as the LLM abstraction
layer.

### Steps

1.  Create an account:

https://openrouter.ai

2.  Generate an API key.
  > OpenRouter offers a free API key with some usage limitations. This allows you to test and run the framework without payment, though higher usage or premium models may require a paid plan.

3.  Configure the AI Engine:

``` bash
cd ai-engine
touch .env
```

4. Add the following key to your environment:

    OPENROUTER_API_KEY=your_api_key_here

> Without a valid API key, the AI Engine will not generate
> recommendations and simulations will fail.

------------------------------------------------------------------------

## AI Engine Configuration


After configuring the LLM provider, you can set up the AI Engine before running the framework by editing the `ai-engine` properties section in `simulator/data/config.yaml`. The engine configuration allows you to define the following behaviors:


1. Selected model:

    The model used by the engine to generate recommendations.

    ```yaml
    ai-engine:
      # other properties
      ai:
        selected_model: google/gemini-2.5-flash # default model
      # other properties
    ```
    > Check the models available in your OpenRouter dashboard and update this value if needed.


2. Scheduler interval:

    The period of time (in seconds) between each recommendation generation by the engine.

    ```yaml
    ai-engine:
      # other properties
      ai:
        scheduler_interval: 60
      # other properties
    ```


3. Graph version:

    The architecture used by the agent for generating recommendations with the selected LLM.

    ```yaml
    ai-engine:
      # other properties
      ai:
        multi_agent: 
          graph_version: v1 # v1 is a single-agent architecture; v2 is a multi-agent architecture
      # other properties
    ```
    > The multi-agent architecture is composed of three agents: performance, cost, and consolidator.

### AI Engine Prompts


By default, the engine includes some predefined prompts. However, you can add new prompts by specifying them in the `simulator/data/config.yaml` file and saving them in the `ai-engine/prompts/` directory.


Two kinds of prompts can be used: one for the `v1 architecture` and another for the `v2 architecture`. Both can be configured as follows:


1. Setting for `v1 architecture` (single agent):

    ```yaml
    ai-engine:
      # other properties
      ai:
        multi_agent: 
          selected_prompt: multi_agent_v3
      # other properties
    ```


2. Setting for `v2 architecture` (multi-agent):

    ```yaml
    ai-engine:
      # other properties
      ai:
        multi_agent: 
          agents:
            prompts:
              performance_prompt_file: performance_agent
              cost_prompt_file: cost_agent
              consolidator_prompt_file: consolidator_agent
      # other properties
    ```

> The prompt names must match the correct file names present in the `ai-engine/prompts/` directory.

------------------------------------------------------------------------

## Multi-Cluster Infrastructure Configuration

The cluster specifications are defined in `simulator/data/config.yaml` and must match the following schema:

``` yaml
clusters:
  member1:
    nodes: 2
    cpu: "8"
    memory: "16Gi"
    autoscaler: false

  member2:
    nodes: 2
    cpu: "8"
    memory: "16Gi"
    autoscaler: true
```

> This schema is the default configuration for the quick start scenario.

------------------------------------------------------------------------

## Workload Definition

The simulator is configured to inject a workload defined in `simulator/data/input.json` using the Broker service.
The structured workload definition must follow the schema below:

```json

{
  "config": {
    "orchestrator": "karmada", // Example for Karmada-based infrastructure
    "namespace": "default",
    "kubeconfig": "karmada.config" // kubeconfig used to submit the workload to the orchestrator
  },
  "data": [
    {
      "id": "frontend",
      "kind": "deployment",
      "action": "create",
      "replicas": "2",
      "cpu": "1", // Number of vCPUs (Kubernetes format, e.g., "1" for 1 core or "1000m" for 1 core)
      "memory": "2", // Memory in Kubernetes format (e.g., "2Gi" for 2 GiB, "2048Mi" for 2048 MiB)
      "job_duration": "",
      "label": "member1", // Cluster label for initial placement
      "timestamp": 1
    },
    {
      "id": "finalizer",
      "kind": "deployment",
      "action": "create",
      "replicas": "2",
      "cpu": "1",
      "memory": "2",
      "job_duration": "",
      "label": "member1",
      "timestamp": 10  // Time (in seconds) when the workload is injected into the system
    }
  ]
}

```

> Note: The broker component will submit each event defined in data from the initial timestamp until the last one. It stops after submitting the last event.

------------------------------------------------------------------------

## Quick Start

### Human-in-the-Loop Mode (Recommended for Demonstrations)

``` bash
make
```

Check the Operator Interface is up and running:

    http://localhost:5173

------------------------------------------------------------------------

### Fully Automated Mode

``` bash
make setup-and-start-auto
```

------------------------------------------------------------------------

## Execution Workflow

1.  Multi-cluster infrastructure provisioning
2.  Workload injection via Broker
3.  Telemetry collection (30-second interval)
4.  AI reasoning cycle (60-second interval)
5.  Recommendation validation (HIL or Auto)
6.  Migration execution via Actuator
7.  Metrics and logs persistence

------------------------------------------------------------------------

## Output and Reproducibility

Each execution generates a timestamped output directory (simulator/data/output/) containing:

-   metrics.json
-   logs/
    -   actuator
    -   broker
    -   monitor
    -   ai-engine

------------------------------------------------------------------------

## Makefile Targets

    make
    make setup-and-start-auto
    make setup
    make run-all-containers
    make run-all-containers-auto
    make stop-all-containers
    make restart-all-containers

------------------------------------------------------------------------

## Research Goals

-   Separation of monitoring, reasoning, validation, and execution
-   Model-agnostic AI integration
-   Transparent human-in-the-loop workflows
-   Reproducible simulation environments
-   Operator accountability and auditability

------------------------------------------------------------------------

## Citation (SBRC)

WASP: Workload Agent-Based Simulation Platform

------------------------------------------------------------------------

## License

Copyright 2026 Laboratório de Sistemas Distribuídos (LSD), Universidade Federal de Campina Grande (UFCG) and Hewlett Packard Enterprise Development LP

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
