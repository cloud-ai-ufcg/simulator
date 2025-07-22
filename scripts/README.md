# KIND + KWOK + Karmada Cluster Simulation with Autoscaler and Prometheus

This repository provides a fully automated local simulation environment for Kubernetes using KIND, KWOK, and Karmada. It supports autoscaling behavior (simulated via KWOK and Cluster Autoscaler), cluster federation with Karmada, and observability with Prometheus.

---

## ✅ Purpose

Offer a reproducible and configurable multi-cluster environment for:

- Validating workload scaling behavior under different resource constraints.
- Testing Cluster Autoscaler interactions with fake KWOK nodes.
- Observing metrics via Prometheus.
- Experimenting with Karmada-based cluster federation and propagation policies.

---

## 🧩 Requirements

Ensure the following tools and conditions:

- Linux or WSL2
- `sudo` privileges
- Docker running
- `bash`, `curl`, `git`, and common CLI tools
- Helm, `kubectl`, `kind`, `yq`, `jq`

---

## ⚙️ Quick Start

### 1. Make all scripts executable

```bash
chmod +x *.sh
```

### 2. Run the main setup script

```bash
./main.sh
```

This script will:

- Parse `initialization.yaml` to load cluster configuration.
- Install prerequisites.
- Launch Karmada and register KIND clusters (`member1`, `member2`).
- Install Prometheus + Grafana in both clusters.
- Install KWOK in both clusters.
- Optionally install Cluster Autoscaler in `member2`.
- Apply KWOK provider config and templates.
- Taint control-plane nodes to prevent pod scheduling.
- Create fake KWOK nodes as specified in the config.

---

## 🗂️ Script Overview

### `main.sh`

Main orchestrator that calls all other scripts in sequence, guided by `initialization.yaml`.

### `initialization.yaml`

Defines resource parameters for each member cluster (number of nodes, CPU, memory, autoscaler toggle).

---

### Setup & Provisioning

| Script | Description |
|--------|-------------|
| `install_prerequisites.sh` | Installs Docker, Kind, kubectl, Helm, yq, etc. |
| `generate_manifests.sh` | Generates propagation policies and workload templates. |
| `install_karmada.sh` | Clones and starts Karmada, labels clusters, applies federation policies. |
| `install_prometheus.sh` | Installs Prometheus in `member1` and `member2` via Helm. |
| `install_kwok.sh` | Deploys KWOK on both clusters using latest GitHub release. |
| `install_autoscaler.sh` | Installs Cluster Autoscaler in `member2` (if enabled in config). Applies KWOK provider configuration. |
| `taint_control_plane.sh` | Adds `NoSchedule` taint to control-plane nodes of both clusters. |
| `create_kwok_nodes.sh` | Applies fake node definitions using resource specs from the config file. |

---

## 📊 Observability

To access **Prometheus** or **Grafana** UIs:

- **Prometheus (member1):** [http://localhost:9090](http://localhost:9090)
- **Prometheus (member2):** [http://localhost:9091](http://localhost:9091)
- **Grafana (member1):** [http://localhost:3000](http://localhost:3000)
- **Grafana (member2):** [http://localhost:3001](http://localhost:3001)

Use the following commands to port-forward manually if needed (the script already starts these in background):

```bash
kubectl config use-context member1   # or member2
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090   # member1 Prometheus
kubectl port-forward -n monitoring svc/prometheus-prometheus 9091:9090   # member2 Prometheus
kubectl port-forward -n monitoring svc/grafana 3000:80                   # member1 Grafana
kubectl port-forward -n monitoring svc/grafana 3001:80                   # member2 Grafana
```

**Grafana default credentials:**

- Username: `adminuser`
- Password: `p@ssword!`

---

## ⚙️ Autoscaler Logs

Check logs in `member2` (if enabled):

```bash
kubectl config use-context member2
kubectl logs -l app.kubernetes.io/instance=autoscaler-kwok -n default
```

---

## 🔄 Reset Environment

To reset everything (KIND clusters, Karmada, manifests, and containers), you can manually stop containers or recreate your workspace. A teardown script is not included yet but can be added.

---

## 📁 Directory Tree

```
scripts/
├── autoscaler/                            # Cluster Autoscaler Helm chart (cloned if not present)
├── clusterpropagationpolicy.yaml          # Example policy for deployment propagation
├── create_kwok_nodes.sh                   # KWOK fake node creator
├── generate_manifests.sh                  # Template and config generator
├── initialization.yaml                    # Cluster config (nodes, CPU, memory, autoscaler)
├── install_autoscaler.sh                  # Helm install for Cluster Autoscaler
├── install_karmada.sh                     # Karmada setup and cluster labeling
├── install_kwok.sh                        # KWOK controller installation in both clusters
├── install_prerequisites.sh               # System tool checker and installer
├── install_prometheus.sh                  # Prometheus setup and port-forward
├── karmada/                               # Karmada repo clone (populated automatically)
├── kwok.kubeconfig                        # Kubeconfig for Autoscaler with KWOK
├── kwok-provider-config.yaml              # Autoscaler configMap for KWOK provider
├── kwok-provider-templates-member1.yaml   # KWOK node template for member1
├── kwok-provider-templates-member2.yaml   # KWOK node template for member2
├── main.sh                                # Master orchestrator
└── taint_control_plane.sh                 # Taints control-plane nodes
```

---

## 📌 Notes

- The system is modular: `main.sh` orchestrates, and each component is replaceable.
- KWOK and the Cluster Autoscaler are decoupled, so you can enable or disable autoscaling in `initialization.yaml` without modifying the core scripts.