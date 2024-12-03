import os
import json
import sys
sys.path.append(os.path.abspath('./'))
from src.Agents.LLM_wrapper import generate_response 

def main():
    project_name = sys.argv[1]
    prompts_directory = f'output/{project_name}/MethodCodeTranslationPrompts'
    prompt_files = os.listdir(prompts_directory)
    for prompt_file in prompt_files:
        print(f"Processing file {prompt_file}")
        with open(os.path.join(prompts_directory, prompt_file), 'r') as file:
            prompt_content = json.load(file)
        for prompt in prompt_content:
            print(f"Processing {prompt['method_name']}")
            if 'translateMethod' in prompt:
                continue
            response = generate_response(prompt['prompt'])
            prompt['translateMethod'] = response  

            with open(os.path.join(prompts_directory, prompt_file), 'w') as file:
                json.dump(prompt_content, file, indent=4)

if __name__ == "__main__":
    main()