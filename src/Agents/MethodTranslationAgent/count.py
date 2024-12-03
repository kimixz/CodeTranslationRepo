import os
import json
import sys

whole_count=0
translated_files_count = 0  # Initialize a counter for translated files
project_name = sys.argv[1]
prompts_directory = f'../../../output/{project_name}/MethodCodeTranslationPrompts'
prompt_files = os.listdir(prompts_directory)
for prompt_file in prompt_files:
    whole_count += 1
    print(f"Processing file {prompt_file}")
    with open(os.path.join(prompts_directory, prompt_file), 'r') as file:
        prompt_content = json.load(file)
    
    file_translated = False  # Flag to check if the current file has any translations

    for prompt in prompt_content:
        print(f"Processing {prompt['method_name']}")
        if 'translateMethod' in prompt:
            file_translated = True  # Set the flag if a translation is added

    if file_translated:
        translated_files_count += 1  # Increment the counter if the file was translated

print(f"Number of translated files: {translated_files_count} out of {whole_count}")