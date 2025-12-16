import json
import random as rd

PATH = "./input/input.json"
OUTPUT_PATH = "./output/input_without_duplicate.json"

data = None
workload_seen = []

def generate_new_id(original_id):
    random_suffix = rd.randint(0, 9999)
    new_id = f"{original_id}-{random_suffix}"

    while new_id in workload_seen:
        random_suffix = rd.randint(0, 9999)
        new_id = f"{original_id}-{random_suffix}"

    return new_id

def search_next_delete(new_id, index, data):
    for i in range(index + 1, len(data["data"])):
        if data["data"][i]["action"] == "delete":
            data["data"][i]["id"] = new_id
            return

def clean_action():
    global workload_seen, data

    idx = 0
    for workload in data["data"]:
        workload_id = workload["id"]

        if workload_id not in workload_seen:
            workload_seen.append(workload_id)
        
        elif workload["action"] != "delete":
            new_id = generate_new_id(workload_id)
            workload["id"] = new_id
            workload_seen.append(new_id)
            search_next_delete(new_id, idx, data)
        
        idx += 1


    with open(OUTPUT_PATH, "w") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)


def clean_duplicates(input_generated, output):
    global data, OUTPUT_PATH
    
    data = input_generated
    OUTPUT_PATH = output

    clean_action()