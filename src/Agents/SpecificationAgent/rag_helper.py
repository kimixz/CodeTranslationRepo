import chromadb
from sentence_transformers import SentenceTransformer
import openai
import os
from dotenv import load_dotenv
from openai import OpenAI
import json
import sys

load_dotenv()

openAIclient = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
model = SentenceTransformer('all-MiniLM-L6-v2')
client = chromadb.PersistentClient(path="./chromadb_data")
with open('projects.json', 'r') as f:
    projects = json.loads(f.read())

def get_project_collection(project_name):
    collection_name = f"{project_name.lower()}_knowledge_base"
    return client.get_collection(name=collection_name)

def embed_query(query, model):
    return model.encode([query])[0]  

def retrieve_documents(query, project_name, model, top_k=5):
    collection = get_project_collection(project_name)
    # Embed the user query
    query_embedding = embed_query(query, model)
    # Perform the similarity search
    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=top_k,
        include=['documents', 'metadatas', 'distances']
    )
    documents = results['documents'][0]  
    metadatas = results['metadatas'][0]  
    distances = results['distances'][0]  
    
    return documents, metadatas, distances

def generate_response(query, documents):
    context = "\n\n".join(documents)
    messages = [
        {"role": "system", "content": "You are a helpful assistant that provides answers based on the provided context."},
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion:\n{query}"}
    ]

    response = openAIclient.chat.completions.create(
        model='gpt-4o',
        messages=messages,
        temperature=0, 
    ).choices[0].message.content.strip()

    return response
    

def rag_pipeline(query, project_name, model):
    documents, metadatas, distances = retrieve_documents(query, project_name, model)
    answer = generate_response(query, documents)
    
    return answer, documents, metadatas

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Error: Missing arguments")
        print("Usage: python rag_helper.py <project_name> <query>")
        print("\nAvailable projects:")
        for project in projects:
            print(f"- {project['name']}")
        exit(1)
    
    project_name = sys.argv[1]
    user_query = ' '.join(sys.argv[2:])
    
    answer, docs, metas = rag_pipeline(user_query, project_name, model)
    
    for project in projects:
        if project['name'] == project_name:
            project['architecture_rag_context'] = answer 
            break

    with open('projects.json', 'w') as f:
        json.dump(projects, f, indent=4)  
    
    # Optionally, display the sources
    # print("\nRetrieved Documents:")
    # for i, (doc, meta) in enumerate(zip(docs, metas)):
    #     print(f"Document {i+1}:")
    #     print(f"Source: {meta['source']}")
    #     print(f"Content Snippet: {doc[:200]}...")  # Show the first 200 characters
    #     print("-" * 80)
