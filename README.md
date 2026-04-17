# 1. Project title

**WASP — Workload Agent-Based Simulation Platform**

WASP is a modular research platform for studying AI-driven workload migration strategies in hybrid and multi-cluster Kubernetes environments. The platform integrates simulation, monitoring, reasoning, validation, and execution in a reproducible and containerized environment, focusing on decision support to recommend migrations that can be validated by operators before execution.

**Paper title:** WASP: Workload Agent-Based Simulation Platform for Migration Recommendations in Federated Kubernetes Environments

**Paper abstract:** Workload migration in federated Kubernetes environments is a complex task, as it requires robust strategies that operate under dynamic conditions to balance performance, cost, and availability. Applying these strategies directly in production, especially with unvalidated autonomous agents, can cause performance degradation. This work presents WASP (Workload Agent-Based Simulation Platform), a decision-support tool that enables simulation of agent-based migration strategies before deployment in production. WASP adopts a modular architecture with monitoring, recommendation, and execution-control layers, and supports configurable policies with human-in-the-loop approval.


# 2. Structure of readme.md

This README is organized into the following sections:

1. Project title and artifact summary;
2. Structure of this README;
3. Badges considered in the evaluation;
4. Basic information (architecture, requirements, and environment);
5. Dependencies (software, external services, and configuration files);
6. Security concerns;
7. Installation;
8. Minimal test;
9. Experiments and claim reproduction;
10. License.

In addition, the WASP repository is composed of services structured as submodules, including, among others, `broker`, `monitor`, `ai-engine`, `recommendations-manager`, as well as infrastructure and analysis scripts.

# 3. Considered badges

The badges considered in the evaluation process are:
- Artefatos Disponíveis (SeloD);
- Artefatos Funcionais (SeloF);
- Artefatos Sustentáveis (SeloS);
- Experimentos Reprodutíveis (SeloR).

# 4. Basic information

## 4.1. Main components

- **Simulator**: orchestrates the simulation timeline and execution flow;
- **Broker**: injects workload and infrastructure events;
- **Monitor**: collects infrastructure telemetry snapshots;
- **AI Engine**: generates structured migration recommendations;
- **Recommendations Manager**: composed of two additional elements, validates and executes approved migrations;
	- **Actuator**: executes migration actions;
	- **Operator Interface** (optional): human validation before execution.

## 4.2. Hardware requirements

**Minimum:**
- CPU: 8 cores
- RAM: 16 GiB
- Disk: 100 GiB SSD

**Recommended:**
- CPU: 12–16 cores
- RAM: 24–32 GiB
- Disk: 100+ GiB NVMe

## 4.3. Software requirements

- Ubuntu 22.04.5 LTS
- GNU Make 4.3
- Docker 28.3.2
- Docker Compose 2.36.2
- Go 1.24

No pre-existing Kubernetes cluster is required. The simulation infrastructure is provisioned automatically.

# 5. Dependencies

## 5.1. Software and service dependencies

- Git submodules for WASP core services (`broker`, `monitor`, `ai-engine`, `recommendations-manager`);
- LLM provider for recommendation generation (by default, we use **OpenRouter**);
- API key used for communication with the provider;

## 5.2. Execution configurations

Before starting the tool, some configurations must be set to define execution parameters and deployment of WASP infrastructure and components.

### 5.2.1. Cluster configuration

Cluster specifications are defined in `simulator/data/config.yaml` and follow the schema below:

```yaml
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

> This schema is the default configuration for the test scenario.

### 5.2.2. Workload configuration

The simulator is configured to submit a workload defined in `simulator/data/input.json`. This submission uses the broker component, which assists WASP with workload submission. The expected structure for the broker input file follows the schema below:

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

> The broker submits each event defined in the file from the initial timestamp to the last timestamp. The component stops submitting events after the final event is submitted.

### 5.2.3. AI Engine configuration

Configuration related to the `ai-engine` component can be set through `simulator/data/config.yaml`.

#### LLM Provider Configuration (Required)

By default, the AI engine uses OpenRouter as the abstraction layer for model usage.

1.  [Create an OpenRouter account;](https://openrouter.ai)

2.  Generate an API key;
  > OpenRouter offers a free API key with some usage limitations. This allows testing and running the framework at no cost, although higher usage or premium models may require a paid plan.

3.  Configure the AI Engine:

```bash
cd ai-engine
touch .env
```
4. Add the following key to your environment:

   `OPENROUTER_API_KEY=your_api_key_here`

> Without a valid API key, the AI Engine will not generate recommendations and simulations will fail.

#### Basic parameters

After defining provider settings, you need to set the following parameters for `ai-engine` operation:

* `scheduler_interval`:
    The period, in seconds, between recommendation generations by `ai-engine`.

    ```yaml
    ai-engine:
      # other properties
      ai:
        scheduler_interval: 60
        # other properties
    ```

* `graph_version`:
    The architecture used by the agent to generate recommendations with the selected model.

    ```yaml
    ai-engine:
      # other properties
      ai:
        multi_agent:
          graph_version: v1 # v1 is related to single-agent architecture; v2 to multi-agent
        # other properties
    ```
    > The multi-agent architecture is composed of three agents: performance, cost, and consolidator.

#### Prompt configuration

By default, the engine includes some predefined prompts. However, you can add new prompts by specifying them in `simulator/data/config.yaml` and saving them in the `ai-engine/prompts/` directory.

Two types of prompts can be used: one for `v1 architecture` and another for `v2 architecture`. Both can be configured as follows:

* Configuration for `v1 architecture` (single agent):

    ```yaml
    ai-engine:
      # other properties
      ai:
        multi_agent:
          selected_prompt: multi_agent_v3
      # other properties
    ```

* Configuration for `v2 architecture` (multi-agent):

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

> Prompt names must exactly match the names of files in the `ai-engine/prompts/` directory.

# 6. Security concerns

- The artifact was designed for research and evaluation environments, not production.
- Standard execution takes place locally in Docker containers.
- The only explicitly required secret in the described flow is `OPENROUTER_API_KEY`, which must be stored in a local `.env` file and must not be versioned.

# 7. Installation

## 7.1. Clone the repository and initialize submodules

```bash
git clone https://github.com/cloud-ai-ufcg/simulator
cd simulator
git submodule update --init --recursive
```

> Not initializing submodules prevents the platform from starting.

## 7.2. Configure the LLM provider (OpenRouter)

1. Create an account at https://openrouter.ai;
2. Generate an API key;
3. Configure the AI Engine environment:

```bash
cd ai-engine
touch .env
```

4. Add to `.env`:

```bash
OPENROUTER_API_KEY=your_api_key_here
```

# 8. Minimal test

You can quickly get started by running the following `make` commands from the root of the WASP repository.

### 8.1. Human-in-the-Loop Mode (Recommended for Demonstrations)

This command sets up infrastructure locally using Docker, prepares all components for safe execution, and then runs a simulation with default input and configuration. The full setup process may take 10 to 20 minutes. When it finishes, the screen shown in Figure 2 appears in the terminal, indicating that the simulation is running. The Operator Interface is available at http://localhost:5173, as shown in Figure 3.

```bash
make
```

![WASP running](simulator_images/wasp_running.jpeg)
<p align="center"><b>Figure 2:</b> Simulation running.</p>

![Operator Interface](simulator_images/operator_interface.jpeg)
<p align="center"><b>Figure 3:</b> Operator Interface.</p>

### 8.2. Fully automated mode (Alternative)

The initial flow of this `make` rule is similar to the previous mode. However, instead of exposing an Operator Interface for human-in-the-loop validation, the Recommendations Manager automatically applies AI Engine recommendations.

```bash
make setup-and-start-auto
```

# 9. Experiments

The default settings for each WASP component in this repository are already aligned with the experiments presented in the paper.

## 9.1. Outputs and reproducibility

Each run generates a timestamped directory in `simulator/data/output/` containing:

- `metrics.json`
- `logs/actuator`
- `logs/broker`
- `logs/monitor`
- `logs/ai-engine`

**How to reproduce (step by step):**
1. Run `make`.
2. Observe the workflow:
	 - Multi-cluster infrastructure provisioning;
   - Component setup
	 - Workload injection by Broker;
	 - Telemetry collection by Monitor (30s interval);
	 - AI Engine reasoning cycle (60s interval);
	 - Validation in the Operator Interface;
	 - Migration execution via Actuator.
3. Collect evidence in logs from each component in `simulator/data/output/`.

> To generate the same charts as in the paper, use the `analyzer`. Move the process data file, saved in `simulator/data/output/`, to the `analyzer_input` directory and run the script `create_plot_for_input.R` to generate the plots in the `plots` directory. You can also use the `create_plot_for_input.R` script to generate plots for any other input file.

**Relevant files/configurations:**
- `simulator/data/config.yaml`
- `simulator/data/input.json`

**Expected time:** 10–20 minutes for setup + scenario duration.

**Expected result:** clear observation of each service role in independent logs.

# 10. LICENSE

Copyright 2026 Laboratório de Sistemas Distribuídos (LSD), Universidade Federal de Campina Grande (UFCG) and Hewlett Packard Enterprise Development LP.

Licensed under the Apache License, Version 2.0.

You may obtain a copy of the license at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under this license is distributed on an "AS IS" basis, without warranties or conditions of any kind.
