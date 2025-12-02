import json
from pathlib import Path
import os

import pandas as pd
import numpy as np
from plotnine import (
    ggplot,
    aes,
    geom_line,
    geom_point,
    labs,
    theme_light,
    scale_x_continuous,
    theme,
    scale_color_manual,
)
import matplotlib.pyplot as plt


def _read_input_json(path: Path) -> pd.DataFrame:
    """
    Lê o JSON de entrada e retorna um DataFrame com os eventos.
    Suporta dois formatos:
      - {"data": [ ... ]}  -> retorna pd.DataFrame(content["data"])
      - [ {...}, {...} ]  -> retorna pd.DataFrame(content)
    """
    if not path.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {path}")

    # Tenta carregar de forma robusta
    with open(path, "r") as f:
        content = json.load(f)

    if isinstance(content, dict) and "data" in content:
        data = content["data"]
    elif isinstance(content, list):
        data = content
    else:
        # Tenta interpretar como DataFrame direto usando pandas (caso seja um objeto com chaves top-level de colunas)
        try:
            df_tmp = pd.read_json(path)
            # se 'data' estava dentro de um frame retornado por read_json, tratamos isso
            if "data" in df_tmp.columns and isinstance(df_tmp.loc[0, "data"], list):
                data = df_tmp.loc[0, "data"]
            else:
                # fallback: converte df_tmp para records
                data = df_tmp.to_dict(orient="records")
        except Exception:
            raise ValueError("Formato de input.json não reconhecido. Deve conter 'data' (lista de eventos) ou ser uma lista de objetos JSON.")

    df = pd.DataFrame(data)
    return df


def validate_columns(df: pd.DataFrame, required_cols):
    missing = [col for col in required_cols if col not in df.columns]
    if missing:
        raise ValueError(f"Columns not found in DataFrame: {missing}")


def process_data(df: pd.DataFrame, interval_seconds: int = 30) -> pd.DataFrame:
    """
    Replica a lógica do notebook:
      - ajusta CPU para 'job' (divide por 100 conforme notebook)
      - adiciona eventos de 'delete' para jobs com 'job_duration'
      - calcula cpu_change, memory_change, pod_change (create = +, delete = -)
      - agrega por intervalo (timestamp // interval_seconds) e retorna o delta por intervalo
    Retorna um DataFrame indexado por 'interval' com colunas:
      ['cpu_change', 'memory_change', 'pod_change']
    """
    # checagem mínima
    validate_columns(df, ["cpu", "memory", "replicas", "action", "timestamp"])

    # garante tipos
    df = df.copy()
    df["timestamp"] = pd.to_numeric(df["timestamp"], errors="coerce").astype(int)
    df["replicas"] = pd.to_numeric(df["replicas"], errors="coerce").fillna(0).astype(int)
    df["cpu"] = pd.to_numeric(df["cpu"], errors="coerce").fillna(0.0).astype(float)
    df["memory"] = pd.to_numeric(df["memory"], errors="coerce").fillna(0.0).astype(float)

    # Ajuste CPU para jobs (conforme notebook)
    if "kind" in df.columns:
        df.loc[df["kind"] == "job", "cpu"] = df.loc[df["kind"] == "job", "cpu"] / 100.0

    # Adiciona eventos de delete para jobs usando job_duration (se disponível)
    if "kind" in df.columns and "job_duration" in df.columns:
        jobs = df[(df["kind"] == "job") & (df["action"] == "create")].copy()
        if not jobs.empty:
            # job_duration pode ser float/int; convertendo para int de segundos
            jobs["timestamp"] = jobs["timestamp"] + jobs["job_duration"].astype(int)
            jobs["action"] = "delete"
            # manter outras colunas iguais
            df = pd.concat([df, jobs], ignore_index=True)

    # Define sinal de mudança: create = +1, delete = -1 (assume outras ações são ignoradas)
    df["sign"] = np.where(df["action"] == "create", 1, np.where(df["action"] == "delete", -1, 0))

    # Calcula mudanças
    df["cpu_change"] = df["cpu"] * df["replicas"] * df["sign"]
    df["memory_change"] = df["memory"] * df["replicas"] * df["sign"]
    df["pod_change"] = df["replicas"] * df["sign"]

    # Agrega por intervalo
    df["interval"] = (df["timestamp"] // interval_seconds).astype(int)
    interval_deltas = df.groupby("interval")[["cpu_change", "memory_change", "pod_change"]].sum()

    return interval_deltas


def plot_cpu_memory(interval_deltas: pd.DataFrame, output_path: Path, title: str = "Disposição dos recursos no input"):
    """
    Gera um plot com duas linhas (CPU azul, Memory vermelho), salva e mostra.
    interval_deltas: DataFrame indexado por 'interval' com colunas cpu_change/memory_change/pod_change
    """
    # Determina range de bins com base no índice
    if interval_deltas.index.size == 0:
        raise ValueError("interval_deltas vazio — sem dados para plotar.")

    max_interval = int(interval_deltas.index.max())
    bins_range = range(0, max_interval + 1)

    # Reindexa preenchendo com zeros para intervalos vazios (assim acumulado fica correto)
    interval_deltas = interval_deltas.reindex(bins_range, fill_value=0)

    # Calcula cumulativos
    interval_deltas["cumulative_cpu"] = interval_deltas["cpu_change"].cumsum()
    interval_deltas["cumulative_memory"] = interval_deltas["memory_change"].cumsum()
    # (não usamos pods nesta figura, mas mantém se quiser)
    interval_deltas["cumulative_pods"] = interval_deltas["pod_change"].cumsum()

    # Prepara formato longo somente com cpu/memory
    df_plot = interval_deltas.reset_index()[["interval", "cumulative_cpu", "cumulative_memory"]].melt(
        id_vars="interval", value_vars=["cumulative_cpu", "cumulative_memory"],
        var_name="metric", value_name="value"
    )

    # Mapear nomes legíveis
    label_map = {"cumulative_cpu": "CPU", "cumulative_memory": "Memória"}
    df_plot["metric_label"] = df_plot["metric"].map(label_map)

    # Gera o plot com plotnine: duas linhas, cores fixas e legenda
    p = (
        ggplot(df_plot, aes(x="interval", y="value", color="metric_label"))
        + geom_line(size=1.2)
        + geom_point(size=1.5)
        + scale_color_manual(values={"CPU": "blue", "Memória": "red"}, name="Recurso")
        + labs(title=title, x=f"Intervalos de 30s (interval index)", y="CPU (Core) e Memória (GiB)")
        + theme_light()
        + theme(figure_size=(12, 5))
        + scale_x_continuous(breaks=list(bins_range))
    )

    # salva e mostra
    output_path.parent.mkdir(parents=True, exist_ok=True)
    p.save(str(output_path), dpi=300)
    print(f"✅ Gráfico salvo em: {output_path}")

    fig = p.draw()
    plt.show()

    return p


def generate_plot(input_path: Path, output_dir: Path, interval_seconds: int = 30, output_name: str = "workloads_cpu_memory_over_time.png"):
    """
    Função principal a ser chamada pelo seu main.
    - input_path: Path para input.json
    - output_dir: Path para diretório de saída
    - interval_seconds: agrupamento em segundos (padrão 30 para compatibilizar com notebook)
    """
    df = _read_input_json(input_path)

    if df.empty:
        raise ValueError("DataFrame lido do input.json está vazio.")

    interval_deltas = process_data(df, interval_seconds=interval_seconds)

    out_path = Path(output_dir) / output_name
    plot_cpu_memory(interval_deltas, out_path)

    pivot = interval_deltas.reset_index()
    pivot["cumulative_cpu"] = pivot["cpu_change"].cumsum()
    pivot["cumulative_memory"] = pivot["memory_change"].cumsum()
    pivot["cumulative_pods"] = pivot["pod_change"].cumsum()
    csv_path = Path(output_dir) / "pod_metrics_summary.csv"
    pivot.to_csv(csv_path, index=False)
    print(f"✅ Pivot CSV salvo em: {csv_path}")

    return out_path


if __name__ == "__main__":
    # teste local: ajusta caminhos conforme necessário
    ROOT = Path(__file__).resolve().parent
    INPUT_FILE = ROOT / "output" / "input.json"
    OUTPUT_DIR = ROOT / "output"

    generate_plot(INPUT_FILE, OUTPUT_DIR)
