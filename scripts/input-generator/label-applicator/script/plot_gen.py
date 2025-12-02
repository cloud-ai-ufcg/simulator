import json
import os
import sys
from collections import defaultdict

try:
    import pandas as pd
except Exception:
    print("Por favor instale pandas: pip install pandas")
    sys.exit(1)

try:
    from plotnine import (
        ggplot, aes, geom_line, geom_point, labs,
        theme_minimal, scale_color_manual, theme, element_text
    )
except Exception:
    print("Por favor instale plotnine: pip install plotnine")
    sys.exit(1)


INPUT_FILE = ""
OUTPUT_FILE = ""


def load_input(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def build_instances(events):
    """
    Transforma eventos em instâncias concretas com start/end:
    - create -> cria instância (start, label, replicas)
    - delete -> fecha a última instância aberta com mesmo id (end = timestamp)
    Suporta múltiplos ciclos create/delete por id.
    """
    # ordenar por timestamp crescente (se timestamps iguais, mantém a ordem original)
    events_sorted = sorted(events, key=lambda e: e.get("timestamp", 0))
    instances = []  # lista de dicts: id, start, end, label, replicas
    # para pareamento de deletes, guardamos instâncias abertas por id
    open_by_id = defaultdict(list)  # id -> list of instance dicts (with end=None)

    for ev in events_sorted:
        action = ev.get("action", "").lower()
        ev_id = ev.get("id")
        ts = ev.get("timestamp")
        # normalizar replicas para int (se existir)
        reps = ev.get("replicas", 0)
        try:
            reps = int(reps)
        except Exception:
            reps = 0

        if action == "create":
            label = ev.get("label", "").lower() if ev.get("label") is not None else ""
            inst = {
                "id": ev_id,
                "start": ts,
                "end": None,
                "label": label,
                "replicas": reps
            }
            instances.append(inst)
            open_by_id[ev_id].append(inst)
        elif action == "delete":
            # find last open inst for this id (LIFO)
            lst = open_by_id.get(ev_id)
            if lst:
                inst = lst.pop()  # pega o mais recente não fechado
                inst["end"] = ts
            else:
                # delete sem create prévio: ignoramos (ou poderíamos logar)
                # simplesmente ignorar
                pass
        else:
            # outras ações (se houver) são ignoradas
            pass

    return instances


def compute_time_series(instances, only_labels=("public", "private")):
    """
    Gera um DataFrame com colunas timestamp, public, private (somas de replicas ativas).
    Consideramos que uma instância está ativa em t se start <= t < end.
    Para instâncias sem end definido, assumimos end = max_timestamp + 1 (para incluí-las no último ponto).
    """
    # coletar timestamps a partir dos eventos start/end existentes
    timestamps = set()
    for inst in instances:
        if inst["start"] is not None:
            timestamps.add(inst["start"])
        if inst["end"] is not None:
            timestamps.add(inst["end"])
    if not timestamps:
        return pd.DataFrame(columns=["timestamp", "public", "private"])

    timestamps = sorted(timestamps)
    max_ts = max(timestamps)
    # caso haja instâncias abertas sem end -> definimos end = max_ts + 1
    default_end = max_ts + 1

    # garantir que consideramos também o último estado no timestamp max_ts
    # (já incluso), e se quisermos mostrar estado "após último evento" poderíamos adicionar default_end-1
    unique_ts = sorted(set(timestamps))

    # preparar séries
    rows = []
    for t in unique_ts:
        sums = {lab: 0 for lab in only_labels}
        for inst in instances:
            s = inst["start"]
            e = inst["end"] if inst["end"] is not None else default_end
            lab = inst["label"]
            reps = inst["replicas"] if inst["replicas"] is not None else 0
            # ativo em t se start <= t < end
            if s is None:
                continue
            if s <= t < e:
                if lab in only_labels:
                    sums[lab] += reps
                else:
                    # rótulos diferentes são ignorados (não entram em public/private)
                    pass
        row = {"timestamp": t}
        row.update(sums)
        rows.append(row)

    df = pd.DataFrame(rows).sort_values("timestamp")
    # caso falte alguma coluna (por segurança), garantir que elas existam
    for lab in only_labels:
        if lab not in df.columns:
            df[lab] = 0
    return df


def plot_and_save(df, out_path):
    # transformar para formato long para plotnine
    df_long = df.melt(id_vars=["timestamp"], value_vars=["public", "private"],
                      var_name="label", value_name="replicas")
    # forçar ordem das labels (opcional)
    df_long["label"] = pd.Categorical(df_long["label"], categories=["public", "private"], ordered=True)

    p = (
        ggplot(df_long, aes(x="timestamp", y="replicas", color="label", group="label"))
        + geom_line(size=1.5)  # linha sólida
        + geom_point(size=3)
        + scale_color_manual(values={"public": "blue", "private": "red"})
        + labs(x="Timestamp (sec)", y="Number of pods", color="Label",
               title="Broker workload distribution")
        + theme_minimal()
        + theme(
            axis_title=element_text(size=10),
            axis_text=element_text(size=9),
            legend_title=element_text(size=10),
            legend_position="right"
        )
    )

    # salvar arquivo
    p.save(str(out_path) + "/", dpi=300, width=10, height=5, units="in")
    print(f"Gráfico salvo em: {out_path}")


def plot_gen(input_path, output_file):
    global INPUT_FILE, OUTPUT_FILE
    
    INPUT_FILE = input_path
    OUTPUT_FILE = output_file

    if not os.path.exists(INPUT_FILE):
        print(f"Arquivo '{INPUT_FILE}' não encontrado no diretório atual ({os.getcwd()}).")
        print("Coloque seu JSON com nome 'input.json' no mesmo diretório e execute novamente.")
        sys.exit(1)

    data = load_input(INPUT_FILE)
    events = data.get("data", [])
    if not events:
        print("Nenhum evento encontrado em 'data' do JSON.")
        sys.exit(1)

    instances = build_instances(events)
    if not instances:
        print("Nenhuma instância construída a partir dos eventos (verifique actions).")
        sys.exit(1)

    df = compute_time_series(instances, only_labels=("public", "private"))
    if df.empty:
        print("Séries vazias (possivelmente rótulos diferentes de 'public'/'private').")
        # ainda assim podemos gerar um gráfico vazio com zeros:
        df = pd.DataFrame({"timestamp": sorted({ev.get("timestamp") for ev in events if ev.get("timestamp") is not None}),
                           "public": [0], "private": [0]})

    plot_and_save(df, OUTPUT_FILE)

