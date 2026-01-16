# Judge/LLM Validator Module

## Visão Geral

O **Judge/LLM Validator** é um módulo intermediário que valida as recomendações geradas pela AI-Engine antes delas serem aplicadas pelo Actuator. Ele utiliza uma LLM (Large Language Model) para avaliar se cada recomendação faz sentido do ponto de vista de negócio, segurança e confiabilidade.

```
┌──────────────┐
│ Monitor      │ (coleta métricas)
└──────┬───────┘
       ↓
┌──────────────┐
│ AI-Engine    │ (gera recomendações)
└──────┬───────┘
       ↓
┌──────────────────────┐
│ Judge/LLM Validator  │ ← NOVO (valida com LLM)
└──────┬───────────────┘
       ↓
┌──────────────┐
│ Actuator     │ (aplica apenas aprovadas)
└──────────────┘
```

## Funcionalidades Principais

1. **Validação Inteligente**: Avalia cada recomendação contra critérios de negócio e segurança
2. **Score de Confiança**: Retorna score 0.0-1.0 indicando quão boa é a recomendação
3. **Justificativa**: Explica por que aprovada ou rejeitada
4. **Auditoria Completa**: Mantém histórico de todas as avaliações
5. **Filtragem Automática**: Envia apenas recomendações aprovadas pro Actuator

## Endpoints Disponíveis

### 1. Health Check
```bash
GET /
```
**Response:**
```json
{
  "status": "healthy",
  "service": "Judge/LLM Validator"
}
```

### 2. Validar Recomendações
```bash
POST /validate
```

**Request:**
```json
{
  "batch_id": 1,
  "recommendations": [
    {
      "workload_id": "1000",
      "destination_cluster": 1,
      "kind": "deployment",
      "current_cluster": 0,
      "cost_reduction": 15,
      "replicas": 3,
      "cpu": "4",
      "memory": "8Gi"
    }
  ],
  "monitoring_data": {
    "cluster_0": {
      "cpu_usage": 45.2,
      "memory_usage": 62.1
    },
    "cluster_1": {
      "cpu_usage": 30.5,
      "memory_usage": 45.3,
      "available_capacity": true
    }
  }
}
```

**Response:**
```json
{
  "batch_id": 1,
  "validated_recommendations": [
    {
      "workload_id": "1000",
      "destination_cluster": 1,
      "kind": "deployment",
      "llm_score": 0.85,
      "llm_status": "approved",
      "llm_reasoning": "Cluster destino tem capacidade e migração economiza 15% sem riscos",
      "original_recommendation": {...}
    }
  ],
  "approved_recommendations": [...],
  "summary": {
    "total_evaluated": 1,
    "approved": 1,
    "rejected": 0,
    "requires_review": 0,
    "approval_rate": 1.0
  }
}
```

### 3. Validar e Aplicar (Full Flow)
```bash
POST /validate-and-apply
```

Mesmo request do `/validate`, mas:
- Valida com LLM
- Extrai recomendações aprovadas
- **Envia automaticamente para o Actuator**
- Retorna resultado da validação + status da aplicação

## Critérios de Avaliação

A LLM avalia cada recomendação usando estes critérios:

1. **Custo-Benefício**: A migração reduz custos sem violar SLA?
2. **Capacidade do Destino**: O cluster destino está saudável e tem capacidade?
3. **Compatibilidade**: O tipo de workload é adequado para migração?
4. **Risco**: Há riscos críticos de produção?
5. **Timing**: O timing da migração é apropriado?

## Integração no Projeto

### Passo 1: Adicionar Judge como Serviço Docker

Criar `judge-validator/Dockerfile`:
```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["python", "judge_llm_validator.py"]
```

### Passo 2: Adicionar ao compose.yaml

```yaml
judge-validator:
  container_name: judge-validator
  build:
    context: ./judge-validator
    dockerfile: Dockerfile
  restart: unless-stopped
  environment:
    - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    - GROQ_API_KEY=${GROQ_API_KEY}
    - GOOGLE_API_KEY=${GOOGLE_API_KEY}
  ports:
    - "8084:8084"
  network_mode: "host"
  depends_on:
    - mongo
```

### Passo 3: Modificar Simulator (breve explicação, não implementado)

Em `simulator/cmd/main.go`, ao invés de chamar diretamente o Actuator:

**Antes:**
```go
aiengine.CallAIEngineAPI() → Actuator (direto)
```

**Depois:**
```go
aiengine.CallAIEngineAPI() → Judge (valida) → Actuator (aplica apenas aprovadas)
```

Ou usar endpoint `/validate-and-apply` do Judge que faz tudo isso internamente.

### Passo 4: Configuração

Adicionar em `simulator/data/config.yaml`:

```yaml
judge:
  host: localhost
  port: 8084
  route: validate-and-apply
  
llm:
  provider: "anthropic"  # ou "groq", "google"
  threshold: 0.7         # Score mínimo para aprovação
```

## Output Explicado

Cada recomendação validada retorna:

```json
{
  "workload_id": "1000",           # ID do workload
  "destination_cluster": 1,        # Para onde ir
  "kind": "deployment",            # Tipo (deployment, job, etc)
  "llm_score": 0.85,              # Confiança (0.0-1.0)
  "llm_status": "approved",       # approved | rejected | requires_review
  "llm_reasoning": "...",         # Por que foi aprovado/rejeitado
  "original_recommendation": {...} # Dados originais
}
```

## Casos de Uso

### 1. Validação Automática
Judge valida e filtra automaticamente, Actuator aplica apenas as boas.

### 2. Auditoria
Judge mantém histórico de decisões para análise posterior.

### 3. Human-in-the-Loop (Futuro)
Recomendações com `requires_review` poderiam aguardar aprovação humana.

### 4. Feedback Loop
Decisões do Judge podem ser usadas para treinar AI-Engine.

## Fluxo Completo

```
1. Simulator → AI-Engine: "Analisa cluster"

2. AI-Engine → Judge: "Aqui estão 10 recomendações"

3. Judge → LLM (10 vezes):
   - "Isso faz sentido?" 
   - LLM retorna: {"decision": "approved", "score": 0.85, ...}

4. Judge → Actuator: "Aplique só essas 7"

5. Actuator → Kubernetes: Migra os workloads

6. Judge → MongoDB: Armazena histórico
```

## Dependências

```
fastapi>=0.104.0
uvicorn>=0.24.0
aiohttp>=3.9.0
pydantic>=2.0.0
anthropic>=0.7.0  # ou groq, google-generativeai, etc
```

## Configurações LLM Suportadas

O módulo suporta qualquer LLM, bastando adaptar a função `_call_llm()`:

- **Anthropic Claude** (padrão)
- **Groq** (rápido, barato)
- **Google Gemini**
- **OpenAI GPT**
- Local (Ollama)

## Próximos Passos para Implementação

1. ✅ Código base criado em `teste/`
2. ⬜ Mover para `judge-validator/` quando pronto
3. ⬜ Criar Dockerfile
4. ⬜ Adicionar ao compose.yaml
5. ⬜ Integrar no Simulator
6. ⬜ Testes e validação
7. ⬜ Documentação de deployment

## Notas Importantes

- Judge **não altera nenhum módulo existente** - é completamente independente
- Pode ser ativado/desativado via configuração
- Fallback seguro: se LLM falhar, rejeita recomendação (safe-by-default)
- Score é apenas referencial, status (approved/rejected) é decisivo
- Todas as decisões são auditadas em MongoDB (opcional)

## Exemplo de Uso Manual

```bash
# Validar recomendações
curl -X POST http://localhost:8084/validate \
  -H "Content-Type: application/json" \
  -d '{
    "batch_id": 1,
    "recommendations": [
      {
        "workload_id": "1000",
        "destination_cluster": 1,
        "kind": "deployment",
        "cost_reduction": 15
      }
    ]
  }'

# Validar E aplicar direto
curl -X POST http://localhost:8084/validate-and-apply \
  -H "Content-Type: application/json" \
  -d '{...}'
```

---

**Status:** Protótipo funcional em `teste/judge_llm_validator.py`  
**Próximo:** Adaptar para produção quando arquitetura for aprovada
