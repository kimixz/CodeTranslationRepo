import os
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

openAIclient = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

def generate_response(query):
    messages = [
        {"role": "system", "content": query}
    ]

    response = openAIclient.chat.completions.create(
        model='gpt-4o',
        messages=messages,
        temperature=0, 
    ).choices[0].message.content.strip()

    return response