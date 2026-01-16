from .log_parser import LogParser
import json
import yaml # type: ignore
from datetime import datetime
class PromptBuilder:
    def __init__(self):
        self.log_parser = LogParser()

    
    def build_prompt(self) -> str:

        metrics = self.open_metrics()
        recomendations = self.open_recomendations()
        count = 1
        for key in recomendations.keys():

            current_recomendation = recomendations[key]
            current_recomendation = self.format_recomendations(current_recomendation)
            
            nearest_key = self.get_nearest_key(key,metrics.keys())
            current_metrics = metrics[nearest_key]
            
            cluster_state = current_metrics["cluster_info"]
            del current_metrics["cluster_info"]
            current_metrics = self.dict_to_yaml(current_metrics)
            cluster_state = self.dict_to_yaml(cluster_state)

            criteria_evaluation = "You must prioritize the cost-benefit ratio between performance and migration costs."
            prompt = self.make_prompt(current_metrics,cluster_state,current_recomendation,criteria_evaluation)

            filename = f"output{count}.txt"
            with open(f"../prompts-test/{filename}","w") as arch:
                arch.write(prompt)
                
            count += 1

    def get_nearest_key(self,key:str,metric_keys:list) -> str:
        copy_metric_keys = list(metric_keys)
        for i in range(len(copy_metric_keys)):
            copy_metric_keys[i] = self.transform_str_to_date(copy_metric_keys[i])
        
        copy_metric_keys.sort()
        key =  self.transform_str_to_date(key)
        for i in range(len(copy_metric_keys)):
            if copy_metric_keys[i] > key:
                return f"{copy_metric_keys[i - 1]}"
            
    def format_recomendations(self,recomendations:list) -> str:
        output = recomendations[0]
        for i in range(1,len(recomendations)):
            output += "\n" + recomendations[i]
        return output

    def transform_str_to_date(self, date:str):
        format_date = "%Y-%m-%d %H:%M:%S"
        return datetime.strptime(date,format_date)
        
    def dict_to_yaml(self,metrics:dict) -> str:
        return yaml.dump(metrics,sort_keys=False)

    def open_metrics(self) -> dict:
        dados = {}
        with open("metrics.json","r",encoding="utf-8") as data:
            dados = json.load(data)
        return dados
    
    def open_recomendations(self) -> dict:
        dados = {}
        with open("recomendations.json","r",encoding="utf-8") as data:
            dados = json.load(data)
        return dados
    
    def make_prompt(self,workloads:str,cluster_state:str,migrations:str,criteria:str) -> str:
        WORKLOADS_YAML = workloads
        CLUSTER_STATE_YAML = cluster_state
        MIGRATIONS_YAML_OR_TEXT = migrations
        CRITERIA_TEXT = criteria

        prompt = f"""
        # ROLE
        You are a Senior Kubernetes Reliability Engineer (SRE) specializing in capacity planning and multi-cluster workload migration.

        # OBJECTIVE
        Your task is to audit and validate a set of migration decisions made by another system. You must determine if each proposed migration is viable and efficient based on resource constraints (CPU/Memory) and specific evaluation criteria.

        # INPUT DATA
        I will provide the following data in YAML format for efficiency:

        <workloads_data>
        {WORKLOADS_YAML}
        </workloads_data>

        <cluster_state>
        {CLUSTER_STATE_YAML}
        </cluster_state>

        <proposed_migrations>
        {MIGRATIONS_YAML_OR_TEXT}
        </proposed_migrations>

        <evaluation_criteria>
        {CRITERIA_TEXT}
        </evaluation_criteria>

        # INSTRUCTIONS
        1. Analyze the resource requirements (CPU/Memory) of each workload in `<workloads_data>`.
        2. Compare them against the available capacity in the destination cluster defined in `<cluster_state>`.
        3. Apply the rules found in `<evaluation_criteria>`.
        4. Validate if the move suggested in `<proposed_migrations>` is a "GO" or "NO-GO".
        5. You must priorize the benefit-cost between performance and cost of migration

        # OUTPUT FORMAT
        Return **ONLY** a valid JSON object. Do not include markdown formatting (like ```json) or conversational text. The JSON must follow this exact schema:

        {{
        "validated_recommendations": [
            {{
            "workload_id": "string (The ID of the workload)",
            "destination_cluster": "string (The target cluster name)",
            "llm_score": number (0.0 to 1.0, where 1.0 is a perfect decision),
            "llm_status": "string ('APPROVED' or 'REJECTED')",
            "llm_reasoning": "string (Concise technical explanation of why the decision is good or bad, citing specific resource metrics)",
            "original_recommendation": "string (The original migration decision text)"
            }}
        ]
        }}
        """
        return prompt

# print(prompt) # Descomente para testar e ver o resultado final
pb = PromptBuilder()
pb.build_prompt()