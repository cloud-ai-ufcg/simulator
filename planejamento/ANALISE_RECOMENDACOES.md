# Análise: Onde e Como a AI-Engine Gera Recomendações

## 📍 Localização no Código

O processo de geração de recomendações ocorre em **3 etapas principais** dentro da AI-Engine:

---

## 1️⃣ ETAPA 1: Análise de Workloads (Geração de Labels)

**Arquivo**: [ai-engine/engine/main.py](ai-engine/engine/main.py#L335)  
**Função**: `analyze_workloads()`

```python
def analyze_workloads(workloads, config, cluster_info=None, interval_duration=None):
    """
    Analyze workloads using the configured AI model.
    Returns:
        Tuple containing (DataFrame with results, explanations dictionary)
    """
    provider = (
        config.get("ai", {}).get("default_config", {}).get("provider", "openrouter")
    )

    # 🔑 AQUI ACONTECE A DECISÃO DA IA
    labels, explanations = label_workloads(
        workloads,
        cluster_info=cluster_info,
        interval_duration=interval_duration,
        provider=provider,
    )

    # Monta DataFrame com resultados
    df = pd.DataFrame(workloads)
    result = df[["workload_id", "kind"]].copy()
    
    # Adiciona a coluna "label" (0, 1, -1)
    # 0 = ficar (private cluster)
    # 1 = migrar (public cluster)
    # -1 = erro/inválido
    result["label"] = numeric_labels.fillna(-1).astype(int)
    
    # Adiciona explicações
    result["reason"] = expl_list

    return result, explanations
```

**O que acontece aqui:**
- `label_workloads()` chama a LLM (via agent system)
- Cada workload recebe um **label**: 0 (ficar), 1 (migrar), -1 (erro)
- Retorna também **explicações** do porque cada decisão

---

## 2️⃣ ETAPA 2: Transformação em Recomendações

**Arquivo**: [ai-engine/engine/util.py](ai-engine/engine/util.py#L519)  
**Função**: `build_workload_recommendations()`

```python
def build_workload_recommendations(
    result_df,
    explanations: Dict[str, Any],
    workloads: List[Dict[str, Any]],
    batch_id: int,
) -> List[WorkloadRecommendation]:
    """
    Transform analysis outputs into WorkloadRecommendation objects.
    """
    # Mapeia origem dos workloads
    origin_by_id = {}
    for w in workloads:
        wid = w.get("workload_id")
        origin_by_id[wid] = w.get("cluster_label", "private")

    explanations_list = (explanations or {}).get("workload_explanations", [])
    recs = []

    # 🔑 LOOP: Constrói recomendação para cada workload
    for idx, row in result_df.iterrows():
        wid = row.get("workload_id")
        kind = row.get("kind")
        label = int(row.get("label", 0))

        origin_label = origin_by_id.get(wid, "private")
        origin_cluster = 0 if origin_label == "private" else 1
        destination_cluster = label

        # Pula recomendações inválidas (-1)
        if destination_cluster == -1:
            continue

        reason = explanations_list[idx] if idx < len(explanations_list) else "..."

        # Cria objeto WorkloadRecommendation
        recs.append(
            WorkloadRecommendation(
                batch_id=batch_id,
                workload_id=wid,
                kind=kind,
                origin_cluster=origin_cluster,
                destination_cluster=destination_cluster,
                reason=reason,
            )
        )

    return recs  # ← LISTA DE RECOMENDAÇÕES
```

**O que acontece aqui:**
- Cada linha do resultado (workload) vira uma `WorkloadRecommendation`
- Inclui: workload_id, kind, origem, destino, justificativa
- Recomendações inválidas são filtradas

---

## 3️⃣ ETAPA 3: Aplicação das Recomendações

**Arquivo**: [ai-engine/api.py](ai-engine/api.py#L223)  
**Função**: `async def run_scheduler()` (dentro de `fetch_metrics`)

```python
async def fetch_metrics():
    """Fetch metrics, analyze, generate recommendations, and apply them."""
    
    # ... (busca métricas do Monitor) ...
    
    # ETAPA 1: Chama analyze_workloads
    result_df, explanations = analyze_workloads(
        workloads,
        app_state.config,
        cluster_info=cluster_info,
        interval_duration=interval_duration,
    )

    # ETAPA 2: Constrói recomendações
    app_state.current_batch_id += 1
    recommendations = build_workload_recommendations(
        result_df, explanations, workloads, app_state.current_batch_id
    )
    
    # Salva em histórico (opcional)
    if history_config.get('enabled', False):
        save_history_batch_recommendations(
            history_config.get('mongodb'),
            current_history_batch_id,
            recommendations  # ← Lista de WorkloadRecommendation
        )

    # ETAPA 3: Envia para Actuator
    await apply_recommendations(recommendations)  # ← AQUI ENVIA
```

---

## 🎯 Como Pegar Apenas as Recomendações Geradas

### **Opção 1: Durante a Execução (Pegar antes de enviar ao Actuator)**

Modifique [ai-engine/api.py](ai-engine/api.py#L234) para capturar antes de aplicar:

```python
# Logo após build_workload_recommendations()
recommendations = build_workload_recommendations(
    result_df, explanations, workloads, app_state.current_batch_id
)

# 👇 AQUI VOCÊ TEM A LISTA DE RECOMENDAÇÕES PURA
print("=== RECOMENDAÇÕES GERADAS ===")
for rec in recommendations:
    print(f"Workload: {rec.workload_id}")
    print(f"  Tipo: {rec.kind}")
    print(f"  De: {rec.origin_cluster} → Para: {rec.destination_cluster}")
    print(f"  Motivo: {rec.reason}")
    print()

# Ou como JSON
import json
recs_json = [rec.to_dict() for rec in recommendations]
print(json.dumps(recs_json, indent=2))

# E DEPOIS enviar ao Actuator (ou ao Judge)
await apply_recommendations(recommendations)
```

### **Opção 2: Via Endpoint HTTP (Sem modificar arquivo)**

Use o endpoint `/analyze` em [ai-engine/api.py](ai-engine/api.py#L301):

```bash
curl -X POST http://localhost:8083/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "workloads": [...],
    "cluster_info": [...]
  }'
```

**Response**: Retorna `{"recommendations": [...]}` contendo as recomendações

### **Opção 3: Salvar em Arquivo JSON**

Modifique `build_workload_recommendations()` para também salvar em arquivo:

```python
def build_workload_recommendations(...) -> List[WorkloadRecommendation]:
    recs = []
    # ... (constrói lista) ...
    
    # Salva em arquivo
    import json
    output_file = f"recommendations_{batch_id}.json"
    with open(output_file, "w") as f:
        json.dump(
            [rec.to_dict() for rec in recs],
            f,
            indent=2,
            ensure_ascii=False
        )
    
    return recs
```

### **Opção 4: Para o Judge (Seu caso específico)**

Se quer enviar direto para Judge em vez de Actuator:

```python
# Em ai-engine/api.py, substitua:
# await apply_recommendations(recommendations)

# Por:
await send_to_judge(
    batch_id=app_state.current_batch_id,
    recommendations=recommendations,
    monitoring_data=processed_data  # Métricas do cluster
)
```

Onde `send_to_judge` seria:

```python
async def send_to_judge(batch_id: int, recommendations: list, monitoring_data: dict):
    """Envia recomendações para o Judge para validação."""
    judge_config = app_state.config.get("judge", {})
    host = judge_config.get("host", "localhost")
    port = judge_config.get("port", 8085)
    route = judge_config.get("route", "validate-and-apply")
    
    url = f"http://{host}:{port}/{route}"
    
    payload = {
        "batch_id": batch_id,
        "recommendations": [rec.to_dict() for rec in recommendations],
        "monitoring_data": monitoring_data
    }
    
    async with aiohttp.ClientSession() as session:
        async with session.post(url, json=payload) as response:
            if response.status == 200:
                logger.info("Sent recommendations to Judge for validation")
                return await response.json()
            else:
                logger.error(f"Failed to send to Judge: {response.status}")
```

---

## 📊 Estrutura de Uma Recomendação

**Arquivo**: [ai-engine/engine/data_types.py](ai-engine/engine/data_types.py)

```python
class WorkloadRecommendation:
    batch_id: int                      # ID do batch de análise
    workload_id: str                   # ID único do workload
    kind: str                          # deployment, job, statefulset, etc
    origin_cluster: int                # 0=private, 1=public (cluster origem)
    destination_cluster: int           # 0=private, 1=public (cluster destino)
    reason: str                        # Explicação da recomendação
```

**Exemplo JSON**:
```json
{
  "batch_id": 1,
  "workload_id": "1000",
  "kind": "deployment",
  "origin_cluster": 0,
  "destination_cluster": 1,
  "reason": "Reduz custo operacional em 15% sem impactar performance"
}
```

---

## 🔄 Fluxo Completo Atual

```
Monitor (8082)
    ↓ (métricas em JSON)
AI-Engine (8083)
    ↓ (processa via /fetch_metrics)
analyze_workloads()
    ↓ (chama label_workloads via LLM)
result_df + explanations
    ↓
build_workload_recommendations()
    ↓ (converte em WorkloadRecommendation list)
recommendations = List[WorkloadRecommendation]
    ↓
apply_recommendations()
    ↓
Actuator (8084)
    ↓
Kubernetes (aplica migrações)
```

---

## 🎯 Fluxo Proposto COM Judge

```
Monitor (8082)
    ↓
AI-Engine (8083)
    ↓
analyze_workloads() → result_df
    ↓
build_workload_recommendations() → List[WorkloadRecommendation]
    ↓
⭐ send_to_judge()  ← NOVO
    ↓
Judge (8085)
    ↓ (valida com LLM)
validated_recommendations + metrics
    ↓
Actuator (8084)
    ↓
Kubernetes
```

---

## 📌 Resumo: Como Interceptar as Recomendações

| Método | Onde | Como |
|--------|------|------|
| **Antes de enviar ao Actuator** | `ai-engine/api.py:234` | Adicione print/save após `build_workload_recommendations()` |
| **Via HTTP** | Endpoint `/analyze` | POST request retorna recomendações |
| **Salvar em arquivo** | `ai-engine/engine/util.py:519` | Adicione JSON dump em `build_workload_recommendations()` |
| **Para o Judge** | `ai-engine/api.py` | Modifique `apply_recommendations()` para `send_to_judge()` |
| **Do MongoDB** | Se history habilitado | Query `judge_decisions` collection |

---

*Criado em: 14 de janeiro de 2026*
