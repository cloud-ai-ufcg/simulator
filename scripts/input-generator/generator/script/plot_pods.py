import os
import json
import pandas as pd
import numpy as np
from plotnine import ggplot, aes, geom_line, geom_point, labs, theme_light, theme, scale_x_continuous
import argparse


def validate_columns(df, required_cols):
    """Verifica se todas as colunas necessárias estão presentes no DataFrame."""
    missing = [col for col in required_cols if col not in df.columns]
    if missing:
        raise ValueError(f"Colunas ausentes no DataFrame: {missing}")


def process_data(df):
    """Processa o DataFrame para calcular as mudanças de pods e agregá-las por intervalo."""
    validate_columns(df, ['cpu', 'memory', 'replicas', 'action', 'timestamp'])

    # Ajuste para jobs
    if 'kind' in df.columns:
        df.loc[df['kind'] == 'job', 'cpu'] = df.loc[df['kind'] == 'job', 'cpu'] / 100

    # Adiciona eventos de deleção com base na duração de jobs
    if 'kind' in df.columns and 'job_duration' in df.columns:
        jobs = df[(df['kind'] == 'job') & (df['action'] == 'create')].copy()
        if not jobs.empty:
            jobs['timestamp'] = pd.to_numeric(jobs['timestamp'], errors='coerce') + pd.to_numeric(
                jobs['job_duration'], errors='coerce'
            ).fillna(0)
            jobs['action'] = 'delete'
            df = pd.concat([df, jobs], ignore_index=True)

    # Converte replicas para número
    df['replicas'] = pd.to_numeric(df['replicas'], errors='coerce').fillna(0)

    # Calcula variação de pods
    df['pod_change'] = df['replicas'] * np.where(df['action'] == 'create', 1, -1)
    df['interval'] = pd.to_numeric(df['timestamp'], errors='coerce').fillna(0) // 30

    # Soma por intervalo
    interval_deltas = df.groupby('interval')[['pod_change']].sum()
    return interval_deltas


def plot_pods(interval_deltas, output_path):
    """Gera e salva o gráfico de quantidade de pods ativos ao longo do tempo."""
    if interval_deltas.empty:
        print("⚠️ Nenhum dado válido para plotar.")
        return pd.DataFrame()

    bins_range = range(int(interval_deltas.index.min()), int(interval_deltas.index.max()) + 1)
    interval_deltas = interval_deltas.reindex(bins_range, fill_value=0)
    interval_deltas['cumulative_pods'] = interval_deltas['pod_change'].cumsum().clip(lower=0)

    # Cria gráfico
    plot = (
        ggplot(interval_deltas.reset_index(), aes(x='interval', y='cumulative_pods'))
        + geom_line(color='blue')
        + geom_point(size=1)
        + labs(
            title='Quantidade de Pods Ativos ao Longo do Tempo',
            x='Tempo (intervalos de 30s)',
            y='Número de Pods Ativos'
        )
        + theme_light()
        + theme(figure_size=(12, 6))
        + scale_x_continuous(breaks=list(bins_range))
    )

    # Salva imagem
    plot.save(output_path, dpi=300)
    print(f"✅ Gráfico salvo em: {output_path}")
    return interval_deltas


def generate_pods_plot(input_path: str, output_dir: str):
    """
    Lê o arquivo JSON informado em 'input_path',
    processa e gera o gráfico de pods ativos.
    """
    if not os.path.isfile(input_path):
        raise FileNotFoundError(f"Arquivo JSON não encontrado: {input_path}")

    os.makedirs(output_dir, exist_ok=True)

    print(f"📄 Lendo dados de: {input_path}")
    with open(input_path, 'r', encoding='utf-8') as f:
        content = json.load(f)

    # O JSON tem estrutura {"config": {...}, "data": [ ... ]}
    if "data" not in content or not isinstance(content["data"], list):
        raise ValueError("O arquivo JSON não contém um campo 'data' válido.")

    df = pd.DataFrame(content["data"])
    if df.empty:
        raise ValueError("O campo 'data' do JSON está vazio.")

    # Ordena e converte colunas numéricas
    df = df.sort_values(by='timestamp').reset_index(drop=True)
    for col in ['timestamp', 'job_duration']:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    interval_deltas = process_data(df)
    output_plot = os.path.join(output_dir, "pods_over_time.png")
    processed_data = plot_pods(interval_deltas, output_plot)

    if processed_data is not None and not processed_data.empty:
        csv_path = os.path.join(output_dir, "pods_summary.csv")
        processed_data.reset_index().rename(
            columns={'interval': 'intervalo', 'cumulative_pods': 'pods_ativos'}
        ).to_csv(csv_path, index=False)
        print(f"📊 CSV salvo em: {csv_path}")
    else:
        print("⚠️ Nenhum dado salvo, pois o DataFrame resultante está vazio.")


def main():
    parser = argparse.ArgumentParser(description="Gera gráfico de pods ativos ao longo do tempo.")
    parser.add_argument("--input", required=True, help="Caminho do arquivo JSON de entrada")
    parser.add_argument("--output", required=True, help="Diretório para salvar o gráfico e o CSV")
    args = parser.parse_args()

    generate_pods_plot(args.input, args.output)


if __name__ == "__main__":
    main()
