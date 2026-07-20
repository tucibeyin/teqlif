import os
import re

ml_modules = [
    "nsfw_service", "feed_als_ml", "churn_ml_service", "clip_service",
    "faiss_service", "image_mod_service", "ml_service", "ner_service",
    "swipe_live_ml", "turkish_nlp"
]

def update_imports():
    backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "app"))
    worker_file = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "app", "worker.py"))
    
    files_to_check = [worker_file]
    for root, dirs, files in os.walk(backend_dir):
        for f in files:
            if f.endswith(".py"):
                files_to_check.append(os.path.join(root, f))
                
    for filepath in set(files_to_check):
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
            
        new_content = content
        for mod in ml_modules:
            new_content = re.sub(rf"from app\.services\.{mod} import", rf"from app.services.ml.{mod} import", new_content)
            new_content = re.sub(rf"import app\.services\.{mod}", rf"import app.services.ml.{mod}", new_content)
            
        if new_content != content:
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(new_content)
            print(f"Updated imports in {filepath}")

if __name__ == "__main__":
    update_imports()
