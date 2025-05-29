# KIND + KWOK Cluster Setup with Autoscaler and Prometheus

Este repositório automatiza a criação de um cluster local Kubernetes usando KIND e KWOK, integrando o Cluster Autoscaler e Prometheus para simulações de escalabilidade e monitoramento.

---

## ✅ Objetivo

Permitir testes locais de escalonamento automático (Cluster Autoscaler) em um cluster Kubernetes simulado, com suporte a observabilidade via Prometheus. Ideal para fins de aprendizado, experimentação e validação de configurações em ambiente controlado.

---

## 🧩 Pré-requisitos

Antes de iniciar, certifique-se de ter:

- Linux ou WSL (preferencialmente)
- Permissões de superusuário (`sudo`)
- Docker instalado e em execução
- `bash` e ferramentas CLI usuais (`curl`, `git`, etc.)

---

## ⚙️ Como usar


1. **Dê permissão de execução aos scripts:**

   ```bash
   chmod +x *.sh
   ```

2. **Execute o script principal:**

   ```bash
   ./main.sh
   ```

   Esse script irá:
   - Instalar dependências
   - Gerar os manifests
   - Criar o cluster KIND com KWOK
   - Instalar Prometheus
   - Configurar o Cluster Autoscaler

---

## 📜 SCRIPTS

### `main.sh`

Script principal que orquestra toda a automação. Executa os scripts na ordem correta e garante permissões necessárias.

### `install_prerequisites.sh`

Instala dependências essenciais:

- `docker`
- `kind`
- `kubectl`
- `yq`
- `helm`

### `generate_manifests.sh`

Gera os manifests YAML que definem o comportamento do cluster, incluindo recursos customizados e simulações de carga.

### `create_kind_cluster.sh`

Cria o cluster KIND chamado `kwok-cluster`, aplicando as configurações necessárias para simular um ambiente realista com KWOK.

### `install_prometheus.sh`

Instala o Prometheus via Helm Chart oficial, incluindo métricas de kubelet, pods, nodes e autoscaling.

### `ASsetup.sh`

Aplica os ConfigMaps do provider KWOK e cria o Deployment do Cluster Autoscaler. Finaliza a preparação do cluster.

---

## 🧪 Verificação

Verifique os pods:

```bash
kubectl get pods -A
```

Para logs do autoscaler:

```bash
kubectl logs -l app.kubernetes.io/instance=autoscaler-kwok -n default
```