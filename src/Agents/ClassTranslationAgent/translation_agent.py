import os
import json
import sys
sys.path.append(os.path.abspath('./'))
from src.Agents.LLM_wrapper import generate_response 

def main():
    project_name = sys.argv[1]
    prompts_file = f'output/{project_name}/ClassCodeTranslationPrompts/class_prompts.json'
    
    with open(prompts_file, 'r') as file:
        prompts_content = json.load(file)
    for prompt in prompts_content:
        if not prompt['all_methods_translated']:
            continue
        swift_file_name = f"{prompt['file_name']}.swift"
        swift_file_path = os.path.join('output', project_name, 'ClassCodeTranslationPrompts',"code_translations", swift_file_name)
        
        if not os.path.exists(swift_file_path):
            os.makedirs(os.path.dirname(swift_file_path), exist_ok=True)
            with open(swift_file_path, 'w') as swift_file:
                response = generate_response(prompt['prompt']).replace("```swift", "").replace("```", "")
                prompt['translatedFile'] = response  
                swift_file.write(response)
        else:
            print(f"File {swift_file_name} already exists. Skipping write.")

    with open(prompts_file, 'w') as file:
        json.dump(prompts_content, file, indent=4)


if __name__ == "__main__":
    main()