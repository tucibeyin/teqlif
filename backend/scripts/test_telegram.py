import asyncio
import sys
import os

# app modüllerine erişebilmek için backend dizinini sys.path'e ekleyelim
backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(backend_dir)
# .env dosyasının doğru okunabilmesi için çalışma dizinini değiştirelim
os.chdir(backend_dir)

from app.utils.telegram import send_telegram_message
from app.config import settings

async def test_telegram_notifications():
    print("🤖 Telegram Bildirim Test Scripti Başlatılıyor...\n")
    
    if not settings.telegram_bot_token or not settings.telegram_chat_id:
        print("❌ HATA: .env dosyasında TELEGRAM_BOT_TOKEN veya TELEGRAM_CHAT_ID eksik!")
        print("Lütfen önce ayarlarınızı tamamlayın.")
        return

    print("✅ .env ayarları bulundu.")
    print(f"📌 Chat ID: {settings.telegram_chat_id}")
    
    # CASE 1: /register tetiklemesi (Sadece e-posta girdiğinde)
    print("\n📩 [CASE 1] Yeni Kayıt (Register) Bildirimi Gönderiliyor...")
    msg_register = (
        "⏳ <b>Yeni Bir Kullanıcı Kayıt Oldu!</b> (Henüz Onaysız)\n\n"
        "👤 <b>İsim:</b> Test Kullanıcısı\n"
        "📧 <b>E-posta:</b> test.kayit@example.com\n"
        "📱 <b>Telefon:</b> +90 555 123 4567\n"
        "🛠 <i>(Bu bir test mesajıdır)</i>"
    )
    success_1 = await send_telegram_message(msg_register)
    if success_1:
        print("✅ CASE 1 Başarılı: Telegram'a mesaj düştü!")
    else:
        print("❌ CASE 1 Başarısız: Mesaj gönderilemedi. (Logları kontrol edin)")

    # Sunucuyu yormamak ve Telegram limitlerine takılmamak için kısa bir bekleme
    await asyncio.sleep(2)

    # CASE 2: /verify tetiklemesi (E-posta doğrulandığında)
    print("\n📩 [CASE 2] E-posta Onay (Verify) Bildirimi Gönderiliyor...")
    msg_verify = (
        "✅ <b>Kullanıcı E-postasını Onayladı!</b>\n\n"
        "👤 <b>İsim:</b> Test Kullanıcısı\n"
        "📧 <b>E-posta:</b> test.kayit@example.com\n"
        "🛠 <i>(Bu bir test mesajıdır)</i>"
    )
    success_2 = await send_telegram_message(msg_verify)
    if success_2:
        print("✅ CASE 2 Başarılı: Telegram'a mesaj düştü!")
    else:
        print("❌ CASE 2 Başarısız: Mesaj gönderilemedi. (Logları kontrol edin)")

    print("\n🎉 Tüm testler tamamlandı. Telegram botunuzu kontrol edin!")

if __name__ == "__main__":
    asyncio.run(test_telegram_notifications())
