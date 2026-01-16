import os
import sys
from pathlib import Path
from openai import OpenAI
import dotenv

from prompt.builder.prompt_builder import PromptBuilder

dotenv.load_dotenv()

client = OpenAI(
    base_url="https://openrouter.ai/api/v1",
    api_key=os.getenv("OPENROUTER_API_KEY")
)
def send_prompt() -> str:
    prompt = PromptBuilder().build_prompt()

    try:
        response = client.chat.completions.create(model='gpt-3.5-turbo',messages=[
            {"role":"user","content":prompt}])
        
        return response.choices[0].message.content
    except Exception as e:
        return "deu vasco"

output = send_prompt()
print(output)        