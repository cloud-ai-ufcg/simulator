FROM ubuntu:22.04

# avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash curl wget git ca-certificates sudo jq \
    iproute2 python3 python3-pip python3-venv docker.io \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies
RUN pip3 install --no-cache-dir --upgrade pip \
    && if [ -f "./requirements.txt" ]; then pip3 install --no-cache-dir -r ./requirements.txt; fi

# Instalar kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Instalar kind
RUN curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64 \
    && chmod +x /usr/local/bin/kind

# Instalar karmadactl
RUN curl -LO https://github.com/karmada-io/karmada/releases/download/v1.9.0/karmadactl-linux-amd64.tgz \
    && tar -zxf karmadactl-linux-amd64.tgz \
    && chmod +x karmadactl \
    && mv karmadactl /usr/local/bin/ \
    && rm karmadactl-linux-amd64.tgz

# Definir diretório de trabalho
WORKDIR /workspace

# Como o Dockerfile está DENTRO da pasta scripts, 
# o "." refere-se ao conteúdo de scripts/
COPY . .

# Garante permissão em todos os arquivos .sh copiados para a raiz de /workspace
RUN chmod +x ./*.sh

# O caminho agora é direto, pois o main.sh está na raiz de /workspace
ENTRYPOINT ["/workspace/main.sh", "--server"]