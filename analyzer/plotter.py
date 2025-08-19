import os
import pandas as pd
import warnings
from plotnine.exceptions import PlotnineWarning
from plotnine import (
    ggplot, aes, geom_step, labs, geom_vline, facet_wrap, 
    scale_color_manual, scale_linetype_manual, scale_x_continuous,
    theme_bw
)

warnings.filterwarnings("ignore", category=PlotnineWarning)
os.environ['LIBGL_DEBUG'] = 'quiet'

def plot_cpu_load(df, output_dir):
    """Plot CPU load by cluster over time using plotnine."""
    plot_df = df.melt(id_vars=['time_seconds'], value_vars=['cpu_load_private', 'cpu_load_public'],
                        var_name='Cluster', value_name='CPU Load')
    plot_df['Cluster'] = plot_df['Cluster'].map({'cpu_load_private': 'Private', 'cpu_load_public': 'Public'})

    max_time = df['time_seconds'].max()    
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))


    g = (
        ggplot(plot_df, aes(x='time_seconds', y='CPU Load', color='Cluster'))
        + geom_step(size=1.5)
        + labs(title="CPU Load by Cluster over time", y="CPU Load", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + theme_bw()
    )

    output_path = os.path.join(output_dir, "cpu_load.png")
    g.save(output_path, width=12, height=6, dpi=300)

def plot_memory_load(df, output_dir):
    """Plot memory load by cluster over time using plotnine."""
    plot_df = df.melt(id_vars=['time_seconds'], value_vars=['mem_load_private', 'mem_load_public'],
                        var_name='Cluster', value_name='Memory Load')
    plot_df['Cluster'] = plot_df['Cluster'].map({'mem_load_private': 'Private', 'mem_load_public': 'Public'})

    max_time = df['time_seconds'].max()
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))


    g = (
        ggplot(plot_df, aes(x='time_seconds', y='Memory Load', color='Cluster'))
        + geom_step(size=1.5)
        + labs(title="Memory Load by Cluster over time", y="Memory Load", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + theme_bw()
    )

    output_path = os.path.join(output_dir, "memory_load.png")
    g.save(output_path, width=12, height=6, dpi=300)

def plot_total_percent_pending(df, output_dir):
    """Plot total percent pending pods over time."""
    max_time = df['time_seconds'].max() if not df.empty else 0
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))

    # Create a copy of the dataframe to avoid modifying the original
    plot_df = df.copy()
    plot_df['total_percent_pending'] = plot_df['total_percent_pending'] * 100

    g = (
        ggplot(plot_df, aes(x='time_seconds', y='total_percent_pending'))
        + geom_step(color='black', size=1)
        + labs(title="Total Percent Pending over time", y="Percent Pending (%)", x="Time (seconds)")
        + scale_x_continuous(breaks=x_breaks)
        + theme_bw()
    )

    output_path = os.path.join(output_dir, "total_percent_pending.png")
    g.save(output_path, width=12, height=6, dpi=300)

def plot_resource(df, value_vars, cap_vars, pending_vars, title, filename, migration_data=None):
    """
    Generates a 4-panel plot for resource usage and pending pods.

    Layout:
    1. Top: Private Cluster - Pending Pods
    2. Mid-Top: Private Cluster - Resource Usage
    3. Mid-Bottom: Public Cluster - Resource Usage
    4. Bottom: Public Cluster - Pending Pods
    """
    df = df.copy()

    # Garante a existência de uma coluna time_seconds começando em 0
    if 'timestamp' in df.columns:
        start_time = df['timestamp'].min()
        df['time_seconds'] = (df['timestamp'] - start_time).dt.total_seconds()
    else:
        df['time_seconds'] = df.index * 60  # Assume intervalos de 1 minuto se não houver timestamp

    min_time = df['time_seconds'].min()
    df['time_seconds'] = df['time_seconds'] - min_time

    # --- 1. Preparação dos dados de Recursos (Uso e Capacidade) ---
    df_usage_melt = df.melt(id_vars=['time_seconds'], value_vars=value_vars, var_name='metric', value_name='value')
    df_usage_melt['cluster'] = df_usage_melt['metric'].apply(lambda x: 'Public' if 'public' in x else 'Private')
    df_usage_melt['type'] = 'Load'

    df_cap_melt = df.melt(id_vars=['time_seconds'], value_vars=cap_vars, var_name='metric', value_name='value')
    df_cap_melt['cluster'] = df_cap_melt['metric'].apply(lambda x: 'Public' if 'public' in x else 'Private')
    df_cap_melt['type'] = 'Capacity'

    plot_df_resources = pd.concat([df_usage_melt, df_cap_melt], ignore_index=True)
    plot_df_resources['plot_group'] = plot_df_resources['cluster'].apply(lambda x: f'{x} Cluster Resources')

    # --- 2. Preparação dos dados de Pods Pendentes ---
    df_pending_melt = df.melt(id_vars=['time_seconds'], value_vars=pending_vars, var_name='metric', value_name='value')
    df_pending_melt['cluster'] = df_pending_melt['metric'].apply(lambda x: 'Public' if 'public' in x else 'Private')
    df_pending_melt['type'] = 'Pending'
    df_pending_melt['plot_group'] = df_pending_melt['cluster'].apply(lambda x: f'{x} Cluster Pending Pods')

    # --- 3. Combina os DataFrames e define a ordem dos gráficos ---
    plot_df = pd.concat([plot_df_resources, df_pending_melt], ignore_index=True)

    plot_order = [
        'Private Cluster Pending Pods',
        'Private Cluster Resources',
        'Public Cluster Resources',
        'Public Cluster Pending Pods'
    ]
    plot_df['plot_group'] = pd.Categorical(plot_df['plot_group'], categories=plot_order, ordered=True)

    categories = [
        'Load', 'Capacity', 'Pending', 'Migration to Private',
        'Migration to Public', 'Both Migrations', 'No Migration'
    ]
    plot_df['type'] = pd.Categorical(plot_df['type'],
                                   categories=categories,
                                   ordered=True)
    plot_df = plot_df.sort_values('type')

    # Mapas de cores e tipos de linha
    color_map = {
        'Load': '#d62728', 'Capacity': '#1f77b4', 'Pending': '#8c564b',
        'Migration to Private': '#9467bd', 'Migration to Public': '#ff7f0e', 'Both Migrations': '#2ca02c', 'No Migration': '#5f615f',
    }
    linetype_map = {
        'Load': 'solid', 'Capacity': 'dashed', 'Pending': 'solid',
        'Migration to Private': 'dotted', 'Migration to Public': 'dotted', 'Both Migrations': 'dotted', 'No Migration': 'dotted'
    }

    # Calcula os intervalos do eixo X
    max_time = df['time_seconds'].max()
    x_breaks = list(range(0, int(max_time) + 120, 120))
    if len(x_breaks) > 20:
        x_breaks = list(range(0, int(max_time) + 300, 300))
    elif len(x_breaks) < 4:
        x_breaks = list(range(0, int(max_time) + 15, 15))

    # --- 4. Criação do Gráfico com ggplot ---
    g = (
        ggplot(plot_df)
        + geom_step(
            aes(x='time_seconds', y='value', color='type', linetype='type'),
            size=1.5,
            na_rm=True
        )
        + facet_wrap(
            '~plot_group',
            ncol=1,
            scales='free_y',
            labeller=lambda x: x.replace(" Resources", "").replace(
                " Pending Pods", "\n(Pending Pods)"
            )
        )
        + labs(title=title, y='Value', x='Time (seconds)', color='Legend', linetype='Legend')
        + scale_x_continuous(breaks=x_breaks, limits=(0, max_time))
        + theme_bw()
    )

    # Adiciona linhas verticais para migrações (será aplicado em todos os painéis)
    if migration_data is not None and not migration_data.empty:
        migration_data = migration_data.copy()
        migration_map = {
            'private': 'Migration to Private',
            'public': 'Migration to Public',
            'both': 'Both Migrations',
            'no migration': 'No Migration'
        }
        migration_data['mig_legend'] = migration_data['type'].map(migration_map)
        migration_data['xintercept'] = migration_data['execution'] * 300 - min_time # Define o intervalo para as linhas verticais do AI-Engine
        migration_data = migration_data[
            (migration_data['xintercept'] >= 0) &
            (migration_data['xintercept'] <= max_time)
        ]

        if not migration_data.empty:
            g += geom_vline(
                migration_data,
                aes(
                    xintercept='xintercept',
                    color='mig_legend',
                    linetype='mig_legend'
                ),
                size=1.5,
                show_legend=False
            )

    g += scale_color_manual(name='Legend', values=color_map)
    g += scale_linetype_manual(name='Legend', values=linetype_map)

    # Garante que o diretório de saída exista
    os.makedirs(os.path.dirname(filename) or '.', exist_ok=True)
    # Aumenta a altura para acomodar os 4 gráficos
    g.save(filename, width=16, height=12, dpi=300)
