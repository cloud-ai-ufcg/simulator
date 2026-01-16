# Passos para Implementar o Módulo LLM Validador

## 1. **Criar a Estrutura do Novo Módulo**
   - Criar uma nova pasta `llm-validator/` na raiz do projeto (similar a `actuator`, `monitor`, `ai-engine`)
   - Este será um serviço independente (provavelmente em Python, assim como AI-Engine)
   - Expor via API REST (como os outros serviços fazem)

## 2. **Definir a Interface de Entrada**
   - O módulo deve receber um payload contendo:
     - **Dados originais**: métricas coletadas pelo Monitor
     - **Recomendações da AI-Engine**: lista de migrações sugeridas
     - **Contexto**: estado atual dos clusters, SLAs, etc
   - Endpoint: `POST /llm-validator/evaluate`

## 3. **Construir o Prompt para a LLM**
   - Estruturar um prompt bem definido que inclua:
     - Instruções claras de avaliação (critérios de "boa recomendação")
     - Os dados contextuais formatados
     - Cada recomendação individualizada
     - Pedido explícito para retornar score/justificativa
   - Reutilizar a mesma infraestrutura que AI-Engine usa (Google, Groq, Anthropic APIs)

## 4. **Processar a Resposta da LLM**
   - Parsear a resposta estruturada da LLM
   - Filtrar recomendações com score abaixo de threshold
   - Manter justificativas para auditoria
   - Retornar apenas recomendações aprovadas

## 5. **Integrar no Fluxo do Simulator**
   - Modificar o `Simulator` (Go) para:
     - Receber recomendações da AI-Engine
     - **NOVO**: Chamar LLM-Validator antes do Actuator
     - Passar apenas recomendações filtradas para o Actuator

## 6. **Atualizar o Docker Compose**
   - Adicionar novo serviço `llm-validator` em `compose.yaml`
   - Configurar variáveis de ambiente (LLM provider, API keys, thresholds)
   - Garantir conectividade de rede entre Simulator → LLM-Validator → Actuator

## 7. **Adicionar Logging e Observabilidade**
   - Registrar:
     - Recomendações recebidas da AI-Engine
     - Score da LLM para cada uma
     - Quais foram aprovadas/rejeitadas
     - Justificativas
   - Salvar em MongoDB para análise posterior

## 8. **Atualizar o Makefile**
   - Adicionar targets se necessário (ex: `run-llm-validator`)
   - Atualizar documentação de como usar

## 9. **Definir Configuração YAML**
   - Criar arquivo de config para o validador:
     - Threshold de aprovação (ex: score > 0.7)
     - Modelo LLM a usar
     - Timeout de espera
     - Comportamento em caso de erro (aprovar ou rejeitar por segurança?)

## 10. **Considerar Casos Especiais**
   - E se a LLM falhar? Fallback: rejeitar todas ou usar score padrão?
   - E se todas as recomendações forem rejeitadas? O sistema continua sem migrar?
   - Feedback humano: armazenar aprovações/rejeições da LLM para retreinar?

**Ordem de prioridade:** 1 → 2 → 3 → 4 → 5 → 6 → 9 → 7 → 8 → 10
