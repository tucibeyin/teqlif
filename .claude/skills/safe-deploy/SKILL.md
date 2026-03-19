---
name: safe-deploy
description: Projeyi production'a almadan önce son kontrolleri (git durumu, son commitler) yapar ve güvenli dağıtım adımlarını sunar. Sadece manuel olarak tetiklenmelidir. (Örnek: /safe-deploy)
allowed-tools: Bash, Read
disable-model-invocation: true
---
# Güvenli Deploy Kontrolcüsü

Görev: Projeyi yayına almadan önce her şeyin yolunda olduğundan emin ol ve ardından dağıtımı başlatmam için beni yönlendir.

Lütfen aşağıdaki adımları sırasıyla izle:
1. **Git Kontrolü:** Terminalde `git status` komutunu çalıştırarak commitlenmemiş veya untracked değişiklik olup olmadığını kontrol et. Eğer varsa beni kesinlikle uyar.
2. **Son Değişiklikler:** `git log -n 3 --oneline` komutunu çalıştırarak yayına alınacak son 3 commit'i bana listele ki neyi deploy ettiğimi göreyim.
3. **Script İncelemesi:** Kök dizindeki `deploy.sh` dosyasını hızlıca oku ve scriptin genel olarak hangi işlemleri yapacağını (örneğin git pull, backend servisini restart etme vb.) bana 1-2 cümleyle özetle.
4. **Sonay ve Yönlendirme:** Tüm kontroller temizse ve hazır görünüyorsak, bana şu mesajı ver: "✅ Kontroller tamamlandı! Her şey yayına alınmaya hazır görünüyor. Dağıtımı başlatmak için terminalde `./deploy.sh` komutunu çalıştırabilirsiniz." 
**ÖNEMLİ:** Asla `deploy.sh` scriptini doğrudan kendin çalıştırma, sadece çalıştırılabilir komutu bana sun.