import re

# Genişletilebilir kural seti
BRANDS = {
    "apple": ["apple", "iphone", "macbook", "ipad", "airpods"],
    "samsung": ["samsung", "galaxy"],
    "xiaomi": ["xiaomi", "redmi", "poco"],
    "nike": ["nike", "air force", "jordan"],
    "adidas": ["adidas", "yeezy"],
    "zara": ["zara"],
    # ...
}

MODELS = [
    "iphone 15 pro max", "iphone 15 pro", "iphone 15 plus", "iphone 15",
    "iphone 14 pro max", "iphone 14 pro", "iphone 14 plus", "iphone 14",
    "iphone 13 pro max", "iphone 13 pro", "iphone 13 mini", "iphone 13",
    "iphone 12 pro max", "iphone 12 pro", "iphone 12 mini", "iphone 12",
    "iphone 11 pro max", "iphone 11 pro", "iphone 11",
    "s24 ultra", "s24 plus", "s24",
    "s23 ultra", "s23 plus", "s23",
    "air force 1", "dunk low", "jordan 1"
]

CONDITION_MAP = {
    "sifir": ["sıfır", "sifir", "kutusunda", "jelatin", "kullanilmamis", "kullanılmamış", "yeni"],
    "hasarli": ["kırık", "kirik", "arızalı", "arizali", "hasarlı", "hasarli", "bozuk", "tamir"],
}

def extract_ner(title: str, description: str, category: str = "") -> dict:
    """
    Yerel (Local) Regex ve Kurallı tabanlı yapısal veri çıkarma (NER) motoru.
    Gelişmiş bir NLP modeline gerek kalmadan marka, model ve kondisyonu çıkarır.
    """
    text = (title + " " + (description or "")).lower()
    
    brand = None
    model_name = None
    condition = "ikinci_el"  # Varsayılan
    
    # 1. Brand tespiti
    for b_key, b_aliases in BRANDS.items():
        if any(alias in text for alias in b_aliases):
            brand = b_key
            break
            
    # 2. Model tespiti
    # En uzun model isimlerinden başlayarak eşleştirme yaparız (Örn: iPhone 13 Pro Max -> iPhone 13'ten önce gelir)
    for m in MODELS:
        if m in text:
            model_name = m
            # Eğer marka henüz bulunamadıysa ve telefon ise Apple atayalım (Örnek heuristic)
            if not brand and "iphone" in m:
                brand = "apple"
            elif not brand and "s2" in m:
                brand = "samsung"
            break
            
    # 3. Durum (Condition) tespiti
    for cond_key, cond_aliases in CONDITION_MAP.items():
        # Title içinde kelime bazlı eşleşme (daha kesin sonuç)
        words = re.findall(r'\w+', title.lower())
        if any(alias in words for alias in cond_aliases):
            condition = cond_key
            break
        # Açıklama içinde de bak
        if condition == "ikinci_el":
            if any(alias in text for alias in cond_aliases):
                condition = cond_key
                break
                
    return {
        "brand": brand,
        "model_name": model_name,
        "condition": condition
    }
