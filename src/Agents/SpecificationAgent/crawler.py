import os
import re
import json
import sys
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm
import chromadb
from sentence_transformers import SentenceTransformer

def get_files_from_repo(repo_path):
    text_file_extensions = ['.txt', '.md', '.py', '.java', '.js', '.html', '.css', '.json', '.xml', '.yml', '.yaml']
    file_paths = []
    for root, dirs, files in os.walk(repo_path):
        for file in files:
            if any(file.lower().endswith(ext) for ext in text_file_extensions):
                file_paths.append(os.path.join(root, file))
    return file_paths

def read_file(file_path):
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        return f.read()

def extract_text_from_html(html_content):
    soup = BeautifulSoup(html_content, 'html.parser')
    # Remove script and style elements
    for script_or_style in soup(['script', 'style', 'header', 'footer', 'nav', 'aside']):
        script_or_style.decompose()
    text = soup.get_text(separator=' ')
    return text

def process_text(text):
    text = re.sub(r'\s+', ' ', text)
    text = text.strip()
    return text

def crawl_website(base_url, max_pages=100):
    visited_urls = set()
    to_visit = [base_url]
    texts = []

    while to_visit and len(visited_urls) < max_pages:
        url = to_visit.pop()
        if url in visited_urls:
            continue
        visited_urls.add(url)
        try:
            response = requests.get(url)
            if response.status_code == 200:
                html_content = response.text
                text = extract_text_from_html(html_content)
                texts.append((url, text))
                soup = BeautifulSoup(html_content, 'html.parser')
                for link in soup.find_all('a', href=True):
                    href = link['href']
                    if href.startswith('/'):
                        href = base_url.rstrip('/') + href
                    if href.startswith(base_url) and href not in visited_urls:
                        to_visit.append(href)
        except Exception as e:
            print(f"Error crawling {url}: {e}")
    return texts

def embed_texts(texts, model):
    embeddings = model.encode(texts, show_progress_bar=True)
    return embeddings

def store_embeddings(texts, embeddings, metadatas, collection):
    ids = [str(i) for i in range(len(texts))]
    collection.add(documents=texts, embeddings=embeddings, metadatas=metadatas, ids=ids)

def main():
    model = SentenceTransformer('all-MiniLM-L6-v2')
    client = chromadb.PersistentClient(path="./chromadb_data")
    project_name = sys.argv[1]

    with open('projects.json', 'r') as f:
        projects_data = json.loads(f.read())
    project = next((p for p in projects_data if p['name'] == project_name), None)
    repo_path = project['github']
    base_url = project['website']
    name = project['name']
    collection_name = f"{name.lower()}_knowledge_base"
    collection = client.get_or_create_collection(name=collection_name)

    print(f"\nProcessing {name}...")

    # Process GitHub repository
    print("Processing GitHub repository...")
    file_paths = get_files_from_repo(repo_path)
    texts = []
    metadatas = []
    for file_path in tqdm(file_paths):
        text = read_file(file_path)
        text = process_text(text)
        texts.append(text)
        metadatas.append({'source': file_path, 'project': name})

    print("Crawling website...")
    website_texts = crawl_website(base_url)
    for url, text in tqdm(website_texts):
        text = process_text(text)
        texts.append(text)
        metadatas.append({'source': url, 'project': name})

    print("Embedding texts...")
    embeddings = embed_texts(texts, model)

    # Store embeddings
    print("Storing embeddings in chromadb...")
    store_embeddings(texts, embeddings, metadatas, collection)
    
    print(f"Finished processing {name}!")

if __name__ == "__main__":
    main()
