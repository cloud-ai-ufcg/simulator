import json

input = "./input/input.json"

def check():
    with open(input, "r", encoding="utf-8") as f:
        data = json.load(f)

    created_ids = set()
    orphan_deletes = []

    # Percorre os eventos
    for event in data.get("data", []):
        wid = event.get("id")
        action = event.get("action")

        if action == "create":
            created_ids.add(wid)
        elif action == "delete":
            # Se o delete aparecer sem um create correspondente
            if wid not in created_ids:
                orphan_deletes.append(event)

    if orphan_deletes:
        print("[ERRO]: Foram encontrados deletes sem criação correspondente:")
        for e in orphan_deletes:
            print(f"- ID: {e['id']}")
    else:
        print("Checagem completa")


def check_integrity(input_file):
    global input
    
    input = input_file
    check()

