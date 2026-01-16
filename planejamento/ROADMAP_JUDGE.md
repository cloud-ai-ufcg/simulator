# Roadmap de Implementação: Judge LLM Validator

**Objetivo**: Implementar módulo Judge funcional que valida recomendações da AI-Engine antes do Actuator aplicá-las.

**Data de Início**: 14 de janeiro de 2026  
**Estimativa**: 4-5 sprints (2-3 semanas)

---

## 📋 FASE 1: Setup & Estrutura Base (Sprint 1)

### ✅ 1.1 Estrutura de Pastas
- [ ] Criar `judge-validator/` na raiz do projeto
- [ ] Estrutura interna:
  ```
  judge-validator/
  ├── Dockerfile
  ├── Dockerfile.api
  ├── requirements.txt
  ├── main.py
  ├── config.yaml
  ├── config.yaml.example
  ├── README.md
  ├── api/
  │   ├── __init__.py
  │   └── routes.py
  ├── engine/
  │   ├── __init__.py
  │   ├── judge_engine.py
  │   ├── prompt_builder.py
  │   ├── llm_client.py
  │   └── metrics_collector.py
  ├── models/
  │   ├── __init__.py
  │   ├── request.py
  │   ├── response.py
  │   └── evaluation.py
  ├── db/
  │   ├── __init__.py
  │   └── mongodb_handler.py
  ├── utils/
  │   ├── __init__.py
  │   ├── logger.py
  │   └── config_loader.py
  └── tests/
      ├── __init__.py
      ├── test_judge_engine.py
      └── test_api.py
  ```

### ✅ 1.2 Dependencies (requirements.txt)
```
fastapi>=0.104.0
uvicorn>=0.24.0
aiohttp>=3.9.0
pydantic>=2.0.0
python-dotenv>=1.0.0
pymongo>=4.6.0
anthropic>=0.7.0
openai>=1.0.0
openrouter>=1.0.0
python-json-logger>=2.0.0
pytest>=7.4.0
```

### ✅ 1.3 Config Base (config.yaml)
```yaml
judge:
  name: "Judge LLM Validator"
  version: "1.0.0"
  
server:
  host: 0.0.0.0
  port: 8085
  reload: true

llm:
  provider: "anthropic"  # anthropic, openai, openrouter, google
  model: "claude-3-sonnet-20240229"
  temperature: 0.1
  max_tokens: 4000
  timeout: 30

criteria:
  weights:
    performance_risk: 0.4
    cost_efficiency: 0.3
    compatibility: 0.15
    cascata_risk: 0.1
    headroom_safety: 0.05
  approval_threshold: 0.7
  confidence_threshold: 0.6

mongodb:
  host: "localhost"
  port: 27017
  database: "ai_engine"
  collections:
    metrics: "cluster_metrics"
    decisions: "judge_decisions"
    feedback: "judge_feedback"

ai_engine:
  host: localhost
  port: 8083
  route: "analyze"

actuator:
  host: localhost
  port: 8084
  route: "apply"

monitor:
  host: localhost
  port: 8082
  route: "metrics"

logging:
  level: DEBUG
  file: judge.log
```

### ✅ 1.4 Models (Pydantic)
- [ ] `RecommendationRequest` (do AI-Engine)
- [ ] `ClusterMetrics` (do MongoDB)
- [ ] `JudgmentResponse` (output do Judge)
- [ ] `EvaluationMetrics` (para pesquisa)

**Responsável**: 1-2 dev  
**Tempo**: 1-2 dias

---

## 📋 FASE 2: Core Engine & LLM Integration (Sprint 1-2)

### ✅ 2.1 LLM Client (llm_client.py)
- [ ] Suporte multi-provider (Anthropic, OpenAI, OpenRouter, Google)
- [ ] Provider factory pattern
- [ ] Token counting
- [ ] Error handling & retries
- [ ] Timeout handling
- [ ] Cost tracking

```python
class LLMClient:
    async def evaluate(self, prompt: str, response_format: dict = None) -> str
    async def get_token_count(self, text: str) -> int
    def get_cost(self, tokens_used: int) -> float
```

### ✅ 2.2 Prompt Builder (prompt_builder.py)
Implementar estrutura few-shot com 4 partes:

1. **Sistema**: Explicar tarefa
2. **Instruções**: Critérios de avaliação
3. **Exemplos**: 3-5 migrações boas/ruins (few-shot)
4. **Dados**: Recomendação atual + métricas

```python
class PromptBuilder:
    def build_evaluation_prompt(
        self,
        recommendation: dict,
        cluster_metrics: dict,
        examples: list = None
    ) -> str
    
    def get_examples() -> list  # Retornar few-shot examples
```

### ✅ 2.3 Judge Engine (judge_engine.py)
- [ ] Orquestração principal
- [ ] Buscar métricas do MongoDB
- [ ] Montar prompt
- [ ] Chamar LLM
- [ ] Parse response JSON
- [ ] Calcular scores dos critérios
- [ ] Determinar aprovação/rejeição
- [ ] Coletar métricas de pesquisa

```python
class JudgeEngine:
    async def evaluate_recommendations(
        self,
        recommendations: list,
        batch_id: int
    ) -> JudgmentResponse
    
    async def _fetch_cluster_metrics(self, cluster_id: int) -> dict
    async def _evaluate_single(self, rec: dict) -> dict
    def _calculate_final_score(self, criteria_scores: dict) -> float
    def _should_approve(self, score: float, confidence: float) -> bool
```

**Responsável**: 1-2 dev  
**Tempo**: 3-4 dias

---

## 📋 FASE 3: API & Endpoints (Sprint 2)

### ✅ 3.1 FastAPI Routes (routes.py)
```
GET  /                         → Health check
POST /validate                 → Validar recomendações
POST /validate-and-apply       → Validar + enviar pro Actuator
GET  /decisions/:batch_id      → Histórico de decisões
GET  /metrics/summary          → Métricas agregadas
POST /feedback                 → Feedback pós-migração
```

### ✅ 3.2 Health Check
```json
{
  "status": "healthy",
  "service": "Judge LLM Validator",
  "version": "1.0.0",
  "uptime_seconds": 3600,
  "llm_provider": "anthropic",
  "mongodb_connected": true,
  "recent_evaluations": 42
}
```

### ✅ 3.3 POST /validate
**Input**: Recomendações + contexto  
**Output**: Validações com métricas de pesquisa

### ✅ 3.4 POST /validate-and-apply
Mesmo do acima, mas:
- [ ] Extrai recomendações aprovadas
- [ ] Envia ao Actuator via HTTP
- [ ] Retorna status da aplicação

### ✅ 3.5 Error Handling
- [ ] LLM timeout → Rejeita com log
- [ ] MongoDB indisponível → Fallback seguro
- [ ] JSON inválido → 400 Bad Request
- [ ] Rate limiting → 429 Too Many Requests

**Responsável**: 1-2 dev  
**Tempo**: 2-3 dias

---

## 📋 FASE 4: MongoDB Integration (Sprint 2)

### ✅ 4.1 MongoDB Handler (mongodb_handler.py)
```python
class MongoDBHandler:
    async def save_decision(self, decision: dict) -> str
    async def get_latest_metrics(self, cluster_id: int) -> dict
    async def save_feedback(self, batch_id: int, outcome: dict) -> str
    async def get_decision_history(self, batch_id: int) -> list
    async def get_bias_metrics(self, days: int = 7) -> dict
    async def create_indexes() → None
```

### ✅ 4.2 Collections Schema
```javascript
// judge_decisions
{
  _id: ObjectId,
  batch_id: number,
  workload_id: string,
  timestamp: Date,
  llm_judgment: {...},
  criteria_analysis: {...},
  evaluation_metrics: {...},
  prompt_version: string
}

// judge_feedback
{
  _id: ObjectId,
  batch_id: number,
  workload_id: string,
  actual_outcome: {...},
  performance_delta: number,
  cost_delta: number,
  was_judgment_correct: boolean,
  timestamp: Date
}
```

**Responsável**: 1 dev  
**Tempo**: 1-2 dias

---

## 📋 FASE 5: Metrics Collection (Sprint 2-3)

### ✅ 5.1 Metrics Collector (metrics_collector.py)
Implementar coleta de todas as 8 categorias:

```python
class MetricsCollector:
    def calculate_confidence_level(llm_response: dict) -> float
    def detect_conflicting_criteria(criteria_scores: dict) -> bool
    def extract_criteria_scores(llm_response: dict) -> dict
    def analyze_errors(predicted: str, actual: str = None) -> dict
    def extract_traceability(llm_response: dict) -> dict
    def calculate_bias_metrics(decisions: list) -> dict
    def calculate_roi(tokens_used: int, recommendation_value: float) -> float
```

### ✅ 5.2 Response Format com Métricas
Garantir que EVERY resposta inclua as 8 categorias:
- Confiança & Certeza
- Breakdown de Critérios
- Análise de Erros
- Rastreabilidade
- Tendências & Padrões
- Feedback Loop (pós-decisão)
- Prompt Engineering
- Custo-Benefício

**Responsável**: 1-2 dev  
**Tempo**: 2-3 dias

---

## 📋 FASE 6: Few-Shot Examples & Prompt Optimization (Sprint 3)

### ✅ 6.1 Examples Database
- [ ] Criar 5-10 exemplos de "boas migrações" (aprovadas)
- [ ] Criar 5-10 exemplos de "más migrações" (rejeitadas)
- [ ] Criar 3-5 exemplos "borderline" (difíceis)

Formato:
```json
{
  "example_id": 1,
  "recommendation": {...},
  "cluster_metrics": {...},
  "expected_judgment": "approved",
  "reasoning": "...",
  "difficulty": "easy|medium|hard"
}
```

### ✅ 6.2 Prompt Versions
- [ ] v1: Basic evaluation
- [ ] v2: Multi-criteria com weights
- [ ] v3: Chain-of-thought (melhor raciocínio)
- [ ] v4: Structured output com JSON schema

Salvar em `prompts/` como templates:
```
prompts/
├── judge_v1.txt
├── judge_v2.txt
├── judge_v3.txt
└── judge_v4.txt
```

**Responsável**: 1 dev (pesquisador)  
**Tempo**: 2-3 dias

---

## 📋 FASE 7: Integration & Testing (Sprint 3-4)

### ✅ 7.1 Modificar AI-Engine
No `ai-engine/api.py`, mudar:

**Antes:**
```python
# Envia direto para Actuator
async def send_to_actuator(recommendations):
    # POST to actuator
```

**Depois:**
```python
# Envia para Judge
async def send_to_judge(recommendations, batch_id):
    async with aiohttp.ClientSession() as session:
        async with session.post(
            "http://judge-validator:8085/validate-and-apply",
            json={
                "batch_id": batch_id,
                "recommendations": recommendations,
                "monitoring_data": await fetch_monitoring_data()
            }
        ) as response:
            return await response.json()
```

### ✅ 7.2 Modificar compose.yaml
Adicionar serviço Judge:
```yaml
judge-validator:
  container_name: judge-validator
  build:
    context: ./judge-validator
    dockerfile: Dockerfile
  restart: unless-stopped
  ports:
    - "8085:8085"
  environment:
    - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    - MONGO_URI=mongodb://mongo:27017
  depends_on:
    - mongo
    - ai-engine
  networks:
    - simulator
```

### ✅ 7.3 Unit Tests
- [ ] Test LLM client (mock responses)
- [ ] Test prompt builder
- [ ] Test judge engine logic
- [ ] Test API routes
- [ ] Test MongoDB operations
- [ ] Test error handling

```bash
pytest tests/ -v --cov=judge
```

### ✅ 7.4 Integration Tests
- [ ] Test fluxo completo (AI-Engine → Judge → Actuator)
- [ ] Test com dados reais do Monitor
- [ ] Test failover scenarios
- [ ] Test timeout handling

**Responsável**: 1-2 dev  
**Tempo**: 3-4 dias

---

## 📋 FASE 8: Docker & Deployment (Sprint 4)

### ✅ 8.1 Dockerfile
```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8085

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8085"]
```

### ✅ 8.2 Build & Test Local
```bash
cd judge-validator
docker build -t judge-validator:latest .
docker run -p 8085:8085 judge-validator:latest
```

### ✅ 8.3 Network Setup
- [ ] Garantir conectividade com AI-Engine (8083)
- [ ] Garantir conectividade com Actuator (8084)
- [ ] Garantir conectividade com MongoDB
- [ ] Test DNS resolution entre containers

**Responsável**: 1 dev  
**Tempo**: 1-2 dias

---

## 📋 FASE 9: Monitoring & Observability (Sprint 4)

### ✅ 9.1 Logging
- [ ] Structured logging (JSON)
- [ ] Log levels apropriados
- [ ] Request/response logging
- [ ] Error tracking com stack traces

### ✅ 9.2 Metrics Prometheus (Opcional para fase 1)
- [ ] Contador de avaliações
- [ ] Distribuição de scores
- [ ] Latência de chamadas LLM
- [ ] Taxa de aprovação
- [ ] Erros por tipo

### ✅ 9.3 Health Checks
- [ ] Endpoint `/health` detalhado
- [ ] Check de conectividade MongoDB
- [ ] Check de disponibilidade LLM
- [ ] Readiness probe

**Responsável**: 1 dev  
**Tempo**: 1-2 dias

---

## 📋 FASE 10: Documentação & Finalização (Sprint 5)

### ✅ 10.1 README.md
- [ ] Visão geral
- [ ] Setup local
- [ ] Configuração
- [ ] Endpoints
- [ ] Exemplos de uso
- [ ] Troubleshooting

### ✅ 10.2 API Documentation
- [ ] OpenAPI/Swagger automático (FastAPI)
- [ ] Acessível em `http://localhost:8085/docs`
- [ ] Exemplos de request/response

### ✅ 10.3 Architecture Diagram
- [ ] Fluxo Judge no sistema
- [ ] Integração com outros módulos
- [ ] Data flow

### ✅ 10.4 Atualizar Planejamento
- [ ] Incorporar Judge no README principal
- [ ] Atualizar compose.yaml docs
- [ ] Adicionar Judge ao workflow

**Responsável**: 1 dev  
**Tempo**: 1-2 dias

---

## 🎯 Timeline Resumida

```
Sprint 1 (3-4 dias):
├─ FASE 1: Setup & Estrutura Base
├─ FASE 2 (início): LLM Client
└─ FASE 3 (início): API Routes

Sprint 2 (3-4 dias):
├─ FASE 2 (conclusão): Judge Engine
├─ FASE 3 (conclusão): Endpoints
├─ FASE 4: MongoDB
└─ FASE 5 (início): Metrics

Sprint 3 (3-4 dias):
├─ FASE 5 (conclusão): Metrics Collection
├─ FASE 6: Few-Shot Examples
├─ FASE 7 (início): Integration
└─ Tests

Sprint 4 (2-3 dias):
├─ FASE 7 (conclusão): Integration Tests
├─ FASE 8: Docker & Deployment
└─ FASE 9: Monitoring

Sprint 5 (1-2 dias):
└─ FASE 10: Documentação
```

**Total**: 4-5 semanas (2-3 semanas se time de 3+ devs)

---

## 👥 Alocação de Recursos Recomendada

| Papel | Tempo | Tarefas |
|-------|-------|--------|
| **Backend Dev (1-2)** | 4-5 semanas | Fases 1-9 |
| **Pesquisador/ML** | 2-3 semanas | Fase 6 (exemplos), otimização de prompts |
| **DevOps (0.5)** | 1 semana | Fases 8-9 (Docker, deployment) |
| **QA** | 1-2 semanas | Fases 7, testes, validação |

---

## ✅ Checklist de "Pronto para Produção"

- [ ] Todos os endpoints funcionando
- [ ] MongoDB operacional com dados persistidos
- [ ] Integração completa AI-Engine → Judge → Actuator
- [ ] Testes unitários passando (>80% coverage)
- [ ] Testes integração com sucesso
- [ ] Docker rodando sem erros
- [ ] Logs estruturados e rastreáveis
- [ ] Health checks retornando 200 OK
- [ ] Documentação completa
- [ ] README com exemplos de uso
- [ ] Feedback loop coletando dados corretamente
- [ ] Métricas de pesquisa sendo salvas

---

## 📚 Referências para Implementação

- [FastAPI Best Practices](https://fastapi.tiangolo.com/deployment/docker/)
- [Pydantic Models](https://docs.pydantic.dev/latest/)
- [PyMongo Documentation](https://pymongo.readthedocs.io/)
- [Anthropic API](https://docs.anthropic.com/)
- [Few-shot Prompting Guide](https://platform.openai.com/docs/guides/prompt-engineering)

---

**Próximo Passo**: Escolher 1-2 devs para iniciar FASE 1 assim que esse roadmap for aprovado.

*Criado em: 14 de janeiro de 2026*
