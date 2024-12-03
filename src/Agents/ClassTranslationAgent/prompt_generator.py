import os
import json
import sys


with open('projects.json', 'r') as f:
    projects = json.loads(f.read())

def generate_class_prompt(file_path, ast_content, class_content ,translated_methods, rag_context):
    prompt = f"""
        Please translate the following Java (Android) class from {os.path.basename(file_path)} into Swift.

        Class Content:
        {class_content}

        Translated Methods:
        {json.dumps(translated_methods, indent=2) if translated_methods else "No translated methods available"}

        Abstract Syntax Tree:
        {json.dumps(ast_content, indent=2) if ast_content else "AST not available"}

        High-level Overview of Architecture:
        {rag_context}

        Output Requirement: Return only the translated Swift code for the class. No additional details, explanation, or formatting is required.
        """
    return prompt

def get_rag_context(project_name):
    for project in projects:
        if project['name'] == project_name:
            return project['architecture_rag_context']
    return None
    
def process_project(root_dir, output_file, ast_base_path, project_name):
    ignore_dirs = {'.git', 'node_modules', 'vendor', 'tests', 'build'}
    class_prompts = []
    rag_context = get_rag_context(project_name)
    for root, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in ignore_dirs]
        
        for file in files:
 
            file_path = os.path.join(root, file)
            base_name, ext = os.path.splitext(file)
            if ext != ".java":
                continue

            with open(file_path, 'r', encoding='utf-8') as f:
                class_content = f.read()
            ast_file_path = os.path.join(ast_base_path, f"{base_name}_ast.json")
            if not os.path.exists(ast_file_path):
                continue
            
            with open(ast_file_path, 'r', encoding='utf-8') as f:
                ast_content = json.load(f)
            
            if not ast_content.get('methods'):
                continue
            ast_content_without_methods = {key: value for key, value in ast_content.items() if key != 'methods'}
            
            method_prompts_file = os.path.join('output', project_name, 'MethodCodeTranslationPrompts', f"{base_name}_prompts.json")
            
            # Load the translated methods from the file
            if os.path.exists(method_prompts_file):
                with open(method_prompts_file, 'r', encoding='utf-8') as method_file:
                    translated_methods = json.load(method_file)
            translated_context = [
                {'method_name': method['method_name'], 'translateMethod': method['translateMethod']}
                for method in translated_methods
                if 'method_name' in method and 'translateMethod' in method
            ]
            all_methods_translated = all('translateMethod' in method for method in translated_methods)

            class_prompt = generate_class_prompt(file_path,ast_content_without_methods,class_content,translated_context,rag_context)
            class_prompts.append({
                'file_name': base_name,
                'prompt': class_prompt,
                'all_methods_translated': all_methods_translated
            })
    
    output_file = f"output/{project_name}/ClassCodeTranslationPrompts/class_prompts.json" 
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(class_prompts, f, indent=4)
    

def main():
    project_name = sys.argv[1]
    input_path = f"dataset/{project_name}"
    output_file = f"output/{project_name}/ClassCodeTranslationPrompts/{project_name}_prompts.json"
    ast_base_path = f"output/{project_name}/AST"
    process_project(input_path, output_file, ast_base_path, project_name)

if __name__ == "__main__":
    main()