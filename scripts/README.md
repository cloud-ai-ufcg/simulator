# KIND + KWOK + Karmada Cluster Setup with Autoscaler and Prometheus

This repository automates the creation of a local multi-cluster Kubernetes environment using KIND, KWOK, and Karmada. It integrates the Cluster Autoscaler (in `member2`) and Prometheus (in both `member1` and `member2`) for simulating autoscaling behavior and enabling observability.

---

## ✅ Purpose

Provide a reproducible local environment for testing autoscaling and monitoring setups in a simulated Kubernetes cluster, ideal for learning, experimentation, and controlled validation of scaling configurations.

---

## 🧩 Requirements

Make sure you have the following before starting:

- Linux or WSL (recommended)
- Superuser permissions (`sudo`)
- Docker installed and running
- `bash`, `curl`, `git`, and typical CLI utilities

---

## ⚙️ How to Use

1. **Give execution permissions to all scripts:**

   ```bash
   chmod +x *.sh
   ```

2. **Run the main setup script:**

   ```bash
   ./main.sh
   ```

   This will:
   - Install all prerequisites
   - Generate the required manifests
   - Start Karmada with KIND clusters (`member1`, `member2`)
   - Install Prometheus in `member1` and `member2`
   - Install Cluster Autoscaler in `member2` only

---

## 📜 Scripts Overview

### `main.sh`

Main entrypoint that orchestrates all setup steps, executing each stage in sequence.

### `install_prerequisites.sh`

Installs the following dependencies:

- `docker`
- `kind`
- `kubectl`
- `helm`
- `yq`
- Karmada's CLI components (if applicable)

### `generate_manifests.sh`

Generates necessary YAML files, including ClusterPropagationPolicies and workload simulation templates (e.g., stress deployment), with support for Karmada federation.

### `install_karmada.sh`

Bootstraps the Karmada control plane using `hack/local-up-karmada.sh`, registers `member1` and `member2` clusters, and applies required labels.

### `install_prometheus.sh`

Installs Prometheus via the official Helm Chart. The script runs once per member cluster (`member1`, `member2`), with node selectors pointing to real KIND workers.

### `ASsetup.sh`

Configures the Cluster Autoscaler **only in `member2`**, applies KWOK provider ConfigMaps, and ensures the autoscaler uses the correct kubeconfig with KWOK simulation.

---

## 🧪 Validation

Check pod status:

```bash
kubectl config use-context member2
kubectl get pods -A
```

Check autoscaler logs:

```bash
kubectl logs -l app.kubernetes.io/instance=autoscaler-kwok -n default
```

To forward Prometheus (on either cluster):

```bash
kubectl config use-context member1 # or member2
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

Then open: [http://localhost:9090](http://localhost:9090)