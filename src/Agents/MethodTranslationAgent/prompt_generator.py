import os
import json
import sys

def generate_method_prompt(method_name, method_code, file_path, ast_content):
    prompt = f"""
        Please translate the following Java (Android) method titled {method_name} from {os.path.basename(file_path)} into Swift.

        Input:

        Method Name: {method_name}

        Method Code: {method_code}

        Abstract Syntax Tree: {json.dumps(ast_content, indent=2) if ast_content else "AST not available"}

        Output Requirement: Return only the translated Swift code. No additional details, explanation, or formatting is required.
        """
    return prompt


def extract_methods_from_ast(ast_file_path, java_file_path):
    try:
        # Read the AST file
        with open(ast_file_path, 'r', encoding='utf-8') as f:
            ast_content = json.load(f)
            methods_info = ast_content['methods']

        # Read the Java file
        with open(java_file_path, 'r', encoding='utf-8') as f:
            java_content = f.read()

        methods = []
        for method in methods_info:
            start_pos = method.get('start_position', 0)
            end_pos = method.get('end_position', 0)
            
            if start_pos and end_pos:
                print(f"Extracting method: {method['name']} from {java_file_path}")
                method_code = java_content[start_pos:end_pos]
            else:
                continue 

            methods.append({
                'name': method['name'],
                'code': method_code,
            })

        return methods

    except Exception as e:
        return []
    
def process_project(root_dir, output_file, ast_base_path, project_name):
    ignore_dirs = {'.git', 'node_modules', 'vendor', 'tests', 'build'}
    
    for root, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in ignore_dirs]
        
        for file in files:
 
            file_path = os.path.join(root, file)
            base_name, ext = os.path.splitext(file)
            if ext != ".java":
                continue
                
            ast_file_path = os.path.join(ast_base_path, f"{base_name}_ast.json")
            if not os.path.exists(ast_file_path):
                continue
            
            print(f"Processing {file_path}...")
            methods = extract_methods_from_ast(ast_file_path, file_path)
            print(f"Extracted {len(methods)} methods from {file_path}")
            print("--------------------------------")
            method_prompts = []
            
            for method in methods:
                prompt = generate_method_prompt(
                    method['name'],
                    method['code'],
                    file_path,
                    method.get('ast', {})
                )
                method_prompts.append({
                    'method_name': method['name'],
                    'method_code': method['code'],
                    'prompt': prompt,
                })
            output_file = f"output/{project_name}/MethodCodeTranslationPrompts/{base_name}_prompts.json" 
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(method_prompts, f, indent=2)
    

def main():
    project_name = sys.argv[1]
    input_path = f"dataset/{project_name}"
    output_file = f"output/{project_name}/MethodCodeTranslationPrompts/{project_name}_prompts.json"
    ast_base_path = f"output/{project_name}/AST"
    process_project(input_path, output_file, ast_base_path, project_name)

if __name__ == "__main__":
    main()