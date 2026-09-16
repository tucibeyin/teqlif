import asyncio
import urllib.parse

def url_to_key(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    path = parsed.path
    if path.startswith("/uploads/"):
        return path[len("/uploads/"):]
    if path.startswith("/dm/"):
        return path[len("/dm/"):]
    return path

def extract_domain(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    return parsed.netloc

async def test():
    url = "https://minio1.teqlif.com/uploads/users/avatar.jpg"
    domain = extract_domain(url)
    key = url_to_key(url)
    print(f"Domain: {domain}, Key: {key}")
    
    # Simüle edilmiş metrikler
    metrics = [
        {"node_id": "live1.teqlif.com", "minio_url": "http://10.10.0.1:9010"},
        {"node_id": "live2.teqlif.com", "minio_url": "http://10.10.0.6:9010"}
    ]
    
    matched_internal = None
    for m in metrics:
        nid = m["node_id"]
        # minio1.teqlif.com -> live1.teqlif.com
        expected_nid = domain.replace("minio", "live")
        if nid == expected_nid or nid == domain:
            matched_internal = m["minio_url"]
            break
            
    print(f"Matched internal URL: {matched_internal}")

if __name__ == "__main__":
    asyncio.run(test())
