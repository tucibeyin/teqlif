---
name: create-endpoint
description: FastAPI backend'ine yeni bir özellik (model, schema, router) ekler. Yeni bir veritabanı tablosu veya API uç noktası oluşturmak istediğinde kullan. (Örnek: /create-endpoint payment)
allowed-tools: Read, Grep, Glob, Bash
---
# Backend Endpoint Oluşturucu

Görev: "$ARGUMENTS" isimli yeni özellik için FastAPI standartlarımıza uygun kod dosyalarını oluştur.

Lütfen aşağıdaki adımları sırasıyla izle:
1. **Mevcut Standartları İncele:** `backend/app/models/user.py`, `backend/app/schemas/user.py` ve `backend/app/routers/users.py` dosyalarını okuyarak projemizin isimlendirme kurallarını, SQLAlchemy modellemelerini, Pydantic şema yapılarını ve APIRouter kullanımını kavra.
2. **Model:** `backend/app/models/` dizininde yeni özellik için bir SQLAlchemy tablosu/modeli oluştur.
3. **Schema:** `backend/app/schemas/` dizininde bu özellik için gerekli Pydantic (Base, Create, Response vb.) şemalarını oluştur.
4. **Router:** `backend/app/routers/` dizininde standart CRUD (Create, Read, Update, Delete) işlemlerini barındıran uç noktaları yaz. Yetkilendirme gerektiren yerlerde projenin mevcut güvenlik yapılarını (örneğin auth bağımlılıkları) kullan.
5. **Entegrasyon:** `backend/main.py` dosyasına bu yeni router'ı eklemek için gerekli yönergeleri veya diff'i sun.