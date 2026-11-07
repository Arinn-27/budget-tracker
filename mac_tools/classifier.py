import json
import os
import urllib.request
import urllib.error
from typing import List, Optional

class OllamaClassifier:
    def __init__(self, model_name: Optional[str] = None, host: Optional[str] = None):
        self.model_name = model_name or os.environ.get("OLLAMA_MODEL", "llama3")
        resolved_host = host or os.environ.get("OLLAMA_HOST", "http://localhost:11434")
        self.host = resolved_host.rstrip("/")

    def classify_merchant(self, merchant: str, categories: List[str]) -> Optional[str]:
        """
        Classifies a merchant name into one of the provided categories using a local Ollama instance.
        Returns the category name if classification is successful, otherwise None.
        """
        url = f"{self.host}/api/chat"
        
        categories_str = ", ".join(categories)
        system_prompt = (
            "You are a strict personal finance assistant. Your job is to classify bank transaction merchant descriptions "
            "into exactly one of the provided categories. You must only output the exact category name from the list "
            "and nothing else. No explanation, no extra text, no markdown. If you are not sure or if it does not fit "
            "any category, output 'Miscellaneous'."
        )
        
        user_prompt = f"Categories: {categories_str}\nMerchant: {merchant}\nCategory:"
        
        payload = {
            "model": self.model_name,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            "stream": False,
            "options": {
                "temperature": 0.0
            }
        }
        
        req = urllib.request.Request(
            url, 
            data=json.dumps(payload).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        
        try:
            # Set a 3-second timeout so it doesn't hang if Ollama is asleep or not running
            with urllib.request.urlopen(req, timeout=3.0) as response:
                if response.status == 200:
                    res_body = json.loads(response.read().decode('utf-8'))
                    category_suggestion = res_body.get("message", {}).get("content", "").strip()
                    
                    # Cleanup result
                    category_suggestion = category_suggestion.replace("'", "").replace('"', '').strip()
                    
                    # Validate against known categories
                    for cat in categories:
                        if cat.lower() == category_suggestion.lower():
                            return cat
                    
                    # Substring check if exact match failed
                    for cat in categories:
                        if cat.lower() in category_suggestion.lower():
                            return cat
                            
                    return "Miscellaneous"
        except (urllib.error.URLError, TimeoutError) as e:
            # Ollama not running or timeout
            pass
        except Exception as e:
            # Other errors
            pass
            
        return None
