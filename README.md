# WASP --- Workload Agent-Based Simulation Platform

**WASP (Workload Agent-Based Simulation Platform)** is a modular
research platform for studying AI-driven workload migration strategies
in hybrid and multi-cluster Kubernetes environments.\
It integrates simulation, monitoring, reasoning, validation, and
execution components into a reproducible, containerized environment
designed for:

-   Academic experimentation
-   Demonstrations and teaching
-   Reproducible research workflows
-   Individual experimentation with AI-assisted operations

WASP focuses on **decision-support**, enabling migration recommendations
that can be validated by operators before execution.

------------------------------------------------------------------------

## Overview

WASP provides a controlled experimental environment for evaluating
workload migration strategies under realistic infrastructure
constraints.

### Key Features

-   Multi-cluster Kubernetes simulation (KWOK + Karmada)
-   Telemetry-driven migration recommendations
-   AI-agnostic reasoning engine
-   Human-in-the-Loop (HIL) validation
-   Fully automated execution mode
-   Reproducible experimental runs
-   Containerized microservice architecture

WASP is intended as a **research and evaluation platform**, not a
production orchestration system.

------------------------------------------------------------------------

## Architecture

WASP is composed of loosely coupled services:

-   **Simulator** --- orchestrates execution timeline and scheduling
-   **Broker** --- injects workload and infrastructure events
-   **Monitor** --- collects telemetry snapshots
-   **AI Engine** --- generates structured migration recommendations
-   **Actuator** --- validates and executes approved migrations
-   **Operator Interface (optional)** --- enables human review

Simulator → Broker → Monitor → AI Engine → Operator interface (optional) → Actuator

All components run as containers and are orchestrated via Docker.

![WASP Architecture](simulator_images/wasp_architecture.png)

------------------------------------------------------------------------

## Requirements

Required environment:

-   Docker 28.3
-   GNU Make 4.3
-   Go 1.24

No pre-existing Kubernetes cluster is required.\
The simulation infrastructure is provisioned automatically.

------------------------------------------------------------------------

## Installation

### 1. Clone Repository and Initialize Submodules

WASP uses Git submodules for its core services.

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

3.  Configure the AI Engine:

``` bash
cd ai-engine
touch .env
```

Add:

    OPENROUTER_API_KEY=your_api_key_here

Alternatively:

``` bash
export OPENROUTER_API_KEY=your_api_key_here
```

> Without a valid API key, the AI Engine will not generate
> recommendations and simulations will fail.

------------------------------------------------------------------------

## Multi-Cluster Infrastructure Configuration

Cluster capacity is defined in:

    simulator/data/config.yaml

Example:

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

After modifying the configuration:

``` bash
make setup
```

or

``` bash
make setup-kubernetes-infra
```

------------------------------------------------------------------------

## Workload Definition

Workloads are defined in:

    simulator/data/workload.yaml

Example schema:

``` yaml
config:
  orchestrator: karmada
  namespace: default
  kubeconfig: karmada.config

data:
  - id: frontend
    kind: deployment
    action: create
    replicas: "2"
    cpu: "1"
    memory: "2"
    label: member1
    timestamp: 1

  - id: finalizer
    kind: deployment
    action: create
    replicas: "2"
    cpu: "1"
    memory: "2"
    label: member1
    timestamp: 10
```

The Broker injects events sequentially according to timestamps.

------------------------------------------------------------------------

## Quick Start

### Human-in-the-Loop Mode (Recommended for Demonstrations)

``` bash
make
```

Operator Interface:

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

WASP: Workload Agent-Based Simulation Platform for Migration
Recommendations in Hybrid Kubernetes Environments.

------------------------------------------------------------------------

## License

Copyright 2026 Laboratório de Sistemas Distribuídos (LSD), Universidade Federal de Campina Grande (UFCG)

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
