# 1. Título projeto

**WASP — Workload Agent-Based Simulation Platform**

WASP é uma plataforma modular de pesquisa para estudo de estratégias de migração de workloads orientadas por IA em ambientes Kubernetes híbridos e multi-cluster. A plataforma integra simulação, monitoramento, raciocínio, validação e execução em um ambiente reprodutível e containerizado, com foco em suporte à decisão para recomendar migrações que podem ser validadas por operadores antes da execução.

**Título do artigo:** WASP: Workload Agent-Based Simulation Platform for Migration Recommendations in Federated Kubernetes Environments

**Resumo do artigo:** A migração de workloads em ambientes Kubernetes federados é uma tarefa complexa, pois exige estratégias robustas que operem sob condições dinâmicas para equilibrar desempenho, custo e disponibilidade. Aplicar essas estratégias diretamente em produção, especialmente com agentes autônomos não validados, pode causar degradação de desempenho. Este trabalho apresenta o WASP (Workload Agent-Based Simulation Platform), uma ferramenta de suporte à decisão que permite simular estratégias de migração baseadas em agentes antes da implantação em produção. O WASP adota uma arquitetura modular com camadas de monitoramento, recomendação e controle de execução, além de suportar políticas configuráveis com aprovação human-in-the-loop.


# 2. Estrutura do readme.md

Este README está organizado nas seguintes seções:

1. Título do projeto e resumo do artefato;
2. Estrutura deste README;
3. Selos considerados na avaliação;
4. Informações básicas (arquitetura, requisitos e ambiente);
5. Dependências (software, serviços externos e arquivos de configuração);
6. Preocupações com segurança;
7. Instalação;
8. Teste mínimo;
9. Experimentos e reprodução de reivindicações;
10. Licença.

Além disso, o repositório WASP é composto por serviços estruturados em submódulos que incluem, entre outros, `broker`, `monitor`, `ai-engine`, `recommendations-manager`, além de scripts de infraestrutura e análise.

# 3. Selos Considerados

Os selos considerados são no processo de avaliação: 
- Artefatos Disponíveis (SeloD);
- Artefatos Funcionais (SeloF);
- Artefatos Sustentáveis (SeloS);
- Experimentos Reprodutíveis (SeloR).

# 4. Informações básicas

## 4.1. Componentes principais

- **Simulator**: orquestra linha do tempo e o fluxo de execução da simulação;
- **Broker**: injeta eventos de workload e infraestrutura;
- **Monitor**: coleta snapshots de telemetria da infraestrutura;
- **AI Engine**: gera recomendações estruturadas de migração;
- **Recommendations Manager**: composto por outros dois elementos, valida e executa migrações aprovadas;
	- **Actuator**: executa ações de migração;
	- **Operator Interface** (opcional): validação humana antes da execução.

## 4.2. Requisitos de hardware

**Mínimo:**
- CPU: 8 núcleos
- RAM: 16 GiB
- Disco: 100 GiB SSD

**Recomendado:**
- CPU: 12–16 núcleos
- RAM: 24–32 GiB
- Disco: 100+ GiB NVMe

## 4.3. Requisitos de software

- Ubuntu 22.04.5 LTS
- GNU Make 4.3
- Docker 28.3.2
- Docker Compose 2.36.2
- Go 1.24

Não é necessário cluster Kubernetes pré-existente. A infraestrutura de simulação é provisionada automaticamente.

# 5. Dependências

## 5.1. Dependências de software e serviços

- Submódulos Git para serviços centrais do WASP (`broker`, `monitor`, `ai-engine`, `recommendations-manager`);
- Provedor LLM para a geração de recomendações (por padrão utilizamos o **OpenRouter**);
- Chave de API que será utilizada para a comunicação com o provedor;

## 5.2. Configurações de execução

Antes de iniciar a ferramenta, algumas configurações devem ser realizadas para determinar parâmetros de execução e implantação da infraestrutura e dos componentes do WASP.

### 5.2.1. Configuração de clusters

As especificações dos clusters estão definidas no arquivo `simulator/data/config.yaml` e seguem o seguinte esquema:

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

> Esse esquema é a configuração padrão para o cenário de teste.

### 5.2.2. Configuração de workload

O simulador está configurado para submeter uma carga de trabalho definida no arquivo `simulator/data/input.json`, essa submissão utiliza o componente broker auxilia o WASP com a submissão da carga de trabalho. A estrutura esperada para o arquivo de entrada usada pelo broker segue o esquema abaixo:

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

> O broker vai submeter cada evento definido no arquivo seguindo do timestamp inicial até o último timestamp. O componente irá parar o período de submissões após o último evento ser submetido.

### 5.2.3. Configuração do AI Engine

A configuração relacionada ao componente `ai-engine` pode ser realizada via `simulator/data/config.yaml`. 

#### LLM Provider Configuration (Required)

Por padrão, o AI engine utiliza o OpenRouter como camada de abstração para a utilização dos modelos.

1.  [Crie uma conta no OpenRouter;](https://openrouter.ai)

2.  Gere uma chave de API;
  > O OpenRouter oferece uma chave de API gratuita com algumas limitações de uso. Isso permite testar e executar o framework sem custo, embora um uso mais elevado ou modelos premium possam exigir um plano pago.

3.  Configure o AI Engine:

```bash
cd ai-engine
touch .env
```
4. Adicione a seguinte chave ao seu ambiente:

   `OPENROUTER_API_KEY=your_api_key_here`

> Sem uma chave de API válida, o AI Engine não vai gerar recomendações e as simulações irão falhar.

#### Parâmetros básicas

Após definir as configurações do provedor, é necessário definir os seguintes parâmetros para o funcionamento do ai-engine:

* 'scheduler_interval':
    O periodo, em segundos, entre cada geração das recomendações pela ai-engine.

    ```yaml
    ai-engine:
      # outras propiedades
      ai:
        scheduler_interval: 60
        # outras propiedades
    ```

* 'graph_version':
    A arquitetura usada pelo agente para a geração das recomendações com o modelo selecionado.

    ```yaml
    ai-engine:
      # outras propiedades
      ai:
        multi_agent:
          graph_version: v1 # v1 está relacionada à arquitetura single-agent; v2 à multi-agent 
        # outras propiedades
    ```
    > A arquitetura multi-agent é composta de três agentes: performance, custo, e consolidador.

#### Configuração dos prompts

Por padrão, o engine inclui alguns prompts predefinidos. No entanto, você pode adicionar novos prompts especificando-os no arquivo `simulator/data/config.yaml` e salvando-os no diretório `ai-engine/prompts/`.

Dois tipos de prompts podem ser usados: um para a `arquitetura v1` e outro para a `arquitetura v2`. Ambos podem ser configurados da seguinte forma:

* Configuração para `arquitetura v1` (single agent):

    ```yaml
    ai-engine:
      # outras propiedades
      ai:
        multi_agent: 
          selected_prompt: multi_agent_v3
      # outras propiedades
    ```

* Configuração para `arquitetura v2` (multi-agent):

    ```yaml
    ai-engine:
      # outras propiedades
      ai:
        multi_agent: 
          agents:
            prompts:
              performance_prompt_file: performance_agent
              cost_prompt_file: cost_agent
              consolidator_prompt_file: consolidator_agent
      # outras propiedades
    ```

> Os nomes dos prompts devem corresponder exatamente aos nomes dos arquivos presentes no diretório `ai-engine/prompts/`.

# 6. Preocupações com segurança

- O artefato foi projetado para ambiente de pesquisa e avaliação, não produção.
- A execução padrão ocorre localmente em contêineres Docker.
- O único segredo explicitamente necessário no fluxo descrito é a chave `OPENROUTER_API_KEY`, que deve ser armazenada em arquivo `.env` local e não deve ser versionada.

# 7. Instalação

## 7.1. Clonar o repositório e inicializar submódulos

```bash
git clone https://github.com/cloud-ai-ufcg/simulator
cd simulator
git submodule update --init --recursive
```

> A não inicialização dos submódulos impede a plataforma de iniciar.

## 7.2. Configurar o provedor LLM (OpenRouter)

1. Criar conta em https://openrouter.ai;
2. Gerar chave de API;
3. Configurar ambiente do AI Engine:

```bash
cd ai-engine
touch .env
```

4. Adicionar ao `.env`:

```bash
OPENROUTER_API_KEY=your_api_key_here
```

# 8. Teste mínimo

Você pode começar rapidamente executando os seguintes comandos `make` a partir da raiz do repositório WASP.

### 8.1. Modo Human-in-the-Loop (Recomendado para Demonstrações)

Este comando configura a infraestrutura localmente usando Docker, prepara todos os componentes para uma execução segura e, em seguida, executa uma simulação com a entrada e a configuração padrão. O processo completo de setup pode levar de 10 a 20 minutos. Quando terminar, a tela mostrada na Figura 2 aparecerá no terminal, indicando que a simulação está em execução. A Interface do Operador ficará acessível em http://localhost:5173, conforme mostrado na Figura 3.

```bash
make
```

![WASP em execução](simulator_images/wasp_running.jpeg)
<p align="center"><b>Figura 2:</b> Simulação em execução.</p>

![Interface do Operador](simulator_images/operator_interface.jpeg)
<p align="center"><b>Figura 3:</b> Interface do Operador.</p>

### 8.2. Modo Totalmente Automatizado (Alternativo)

O fluxo inicial desta regra `make` é semelhante ao modo anterior. No entanto, em vez de expor uma Interface do Operador para validação human-in-the-loop, o Recommendations Manager aplicará automaticamente as recomendações do AI Engine.

```bash
make setup-and-start-auto
```

# 9. Experimentos

As configurações padrões para cada componente do WASP neste repositório já estão relacionadas aos experimentos apresentados no artigo.

## 9.1. Saídas e reprodutibilidade

Cada execução gera um diretório com timestamp em `simulator/data/output/` contendo:

- `metrics.json`
- `logs/actuator`
- `logs/broker`
- `logs/monitor`
- `logs/ai-engine`

**Como reproduzir (passo a passo):**
1. Executar `make`.
2. Observar o workflow:
	 - Provisionamento da infraestrutura multi-cluster;
   - Setup dos componentes
	 - Injeção de workload pelo Broker;
	 - Coleta de telemetria pelo Monitor (intervalo de 30s);
	 - Ciclo de raciocínio do AI Engine (intervalo de 60s);
	 - Validação na Operator Interface;
	 - Execução de migração via Actuator.
3. Coletar evidências nos logs de cada componente em `simulator/data/output/`.

**Arquivos/configurações relevantes:**
- `simulator/data/config.yaml`
- `simulator/data/input.json`

**Tempo esperado:** 10–20 minutos para setup + tempo do cenário.

**Resultado esperado:** observar claramente os papéis de cada serviço em logs independentes.

# 10. LICENSE

Copyright 2026 Laboratório de Sistemas Distribuídos (LSD), Universidade Federal de Campina Grande (UFCG) and Hewlett Packard Enterprise Development LP.

Licenciado sob a Apache License, Version 2.0.

Você pode obter uma cópia da licença em:

http://www.apache.org/licenses/LICENSE-2.0

Salvo disposição legal aplicável ou acordo por escrito, o software distribuído sob esta licença é distribuído "como está", sem garantias ou condições de qualquer tipo.
