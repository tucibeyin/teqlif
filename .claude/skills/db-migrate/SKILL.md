---
name: db-migrate
description: Alembic kullanarak FastAPI backend'i için otomatik veritabanı migrasyon dosyası oluşturur. Sadece manuel olarak tetiklenmelidir. (Örnek: /db-migrate add_user_profile_fields)
allowed-tools: Bash, Read, Grep
disable-model-invocation: true
---
# Veritabanı Migrasyon Oluşturucu

Görev: Alembic kullanarak "$ARGUMENTS" mesajıyla yeni bir migrasyon dosyası oluştur.

Lütfen aşağıdaki adımları sırasıyla izle:
1. **Dizine Geç:** İşlemleri `backend/` dizini içerisinde gerçekleştir.
2. **Durumu Kontrol Et:** Veritabanı modelleriyle mevcut durum arasında bir fark olup olmadığını anlamak için kısaca modelleri gözden geçir.
3. **Migrasyonu Başlat:** Terminalde `alembic revision --autogenerate -m "$ARGUMENTS"` komutunu çalıştır.
4. **Kontrol Et:** `backend/alembic/versions/` dizininde yeni oluşturulan dosyayı bul ve içeriğini oku (upgrade ve downgrade fonksiyonlarını kontrol et).
5. **Raporla:** Bana oluşturulan migrasyon dosyasındaki değişikliklerin özetini göster. Eğer her şey doğru görünüyorsa, veritabanına uygulamam için `alembic upgrade head` komutunu önerek işlemi tamamla. Asla benim onayım olmadan `upgrade head` işlemini otomatik yapma.