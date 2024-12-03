

#!/usr/bin/env python3

import papermill as pm
import argparse
import os

def run_notebook(project_name):
    input_notebook = "src/Agents/StaticAnalysisAgent/ASTParser.ipynb"
    output_notebook = f"src/Agents/StaticAnalysisAgent/ASTParser_{project_name}_output.ipynb"
    try:
        pm.execute_notebook(
            input_notebook,
            output_notebook,
            parameters={"project_name": project_name}
        )
    except Exception as e:
        print(f"Error executing notebook: {str(e)}")
        raise

def run_script(script_path, project_name, parameters=None):
    os.system(f"python {script_path} {project_name} {parameters}")

if __name__ == "__main__":
    # Set up argument parser
    parser = argparse.ArgumentParser()
    parser.add_argument('project_name', type=str, help='Name of the project to analyze')
    args = parser.parse_args()
    # run_notebook(args.project_name)

    crawler_script = "src/Agents/SpecificationAgent/crawler.py"
    rag_script = "src/Agents/SpecificationAgent/rag_helper.py"
    method_prompt_script = "src/Agents/MethodTranslationAgent/prompt_generator.py"
    method_translation_script = "src/Agents/MethodTranslationAgent/translation_agent.py"
    class_prompt_script = "src/Agents/ClassTranslationAgent/prompt_generator.py"
    class_translation_script = "src/Agents/ClassTranslationAgent/translation_agent.py"

    # run_script(crawler_script, args.project_name)
    # run_script(rag_script, args.project_name, "Give me a high-level overview of architecture of the project")
    # run_script(method_prompt_script, args.project_name)
    # run_script(method_translation_script, args.project_name)
    run_script(class_prompt_script, args.project_name)
    run_script(class_translation_script, args.project_name)