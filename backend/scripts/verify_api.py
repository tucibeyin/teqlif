import json
import urllib.request
import getpass

BASE_URL = "http://127.0.0.1:8000/api"

def api_request(method, endpoint, token):
    req = urllib.request.Request(f"{BASE_URL}{endpoint}", headers={"Authorization": f"Bearer {token}"}, method=method)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())

def main():
    pw = getpass.getpass("tesbih şifresi: ")
    data = json.dumps({"login_identifier": "tesbih", "password": pw}).encode()
    req = urllib.request.Request(f"{BASE_URL}/auth/login", data=data, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req) as r:
        token = json.loads(r.read().decode())["access_token"]
        
    messages = api_request("GET", "/messages/3", token)
    print("tesbih'in teqlif'ten çektiği mesajlar:")
    for m in messages:
        print(f"[{m['created_at']}] {m['content']}")

if __name__ == "__main__":
    main()
