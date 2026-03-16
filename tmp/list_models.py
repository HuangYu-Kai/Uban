import google.generativeai as genai
import os
from dotenv import load_dotenv

load_dotenv()

def list_available_models():
    # Use the same key as the user for consistency
    api_key = 'AIzaSyDpWwCB0dPbsQWYfbY9ltOzmg58wgLD43c'
    genai.configure(api_key=api_key)
    
    print("--- Available Models ---")
    try:
        for m in genai.list_models():
            if 'generateContent' in m.supported_generation_methods:
                print(f"Name: {m.name}, Display: {m.display_name}")
    except Exception as e:
        print(f"Error listing models: {e}")

if __name__ == "__main__":
    list_available_models()
