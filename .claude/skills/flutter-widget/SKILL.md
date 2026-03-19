---
name: flutter-widget
description: Flutter projesi için tema standartlarına uygun yeni bir widget veya ekran (screen) oluşturur. (Örnek: /flutter-widget CustomButton widget VEYA /flutter-widget Profile screen)
allowed-tools: Read, Grep, Glob
---
# Flutter Bileşen Oluşturucu

Görev: "$ARGUMENTS" temel alınarak yeni bir Flutter bileşeni veya ekranı oluştur. 

Lütfen aşağıdaki adımları sırasıyla izle:
1. **İsteği Analiz Et:** Girdi ($ARGUMENTS) bir `screen` (tam sayfa ekran) mi yoksa bir `widget` (yeniden kullanılabilir küçük bileşen) mı belirliyoruz.
2. **Tasarım Standartlarını Oku:** `mobile/lib/config/app_colors.dart` ve `mobile/lib/config/theme.dart` dosyalarını oku. Yeni oluşturacağın dosyada ASLA hard-coded (sabit) renk veya stil kullanma. Her zaman projenin tanımlı tema ve renk değişkenlerini (ör. `AppColors.primaryBlue`) kullan.
3. **Konumlandırma:** - Eğer widget ise dosyayı `mobile/lib/widgets/` dizininde,
   - Eğer screen ise dosyayı `mobile/lib/screens/` dizininde oluştur.
4. **Kodlama Kuralları:**
   - Dosya adını `snake_case` formatında yap (ör. `custom_button.dart`).
   - Sınıf adını `PascalCase` formatında yap (ör. `CustomButton`).
   - Widget'ın durumuna göre uygun olanı seç (`StatelessWidget` veya `StatefulWidget`).
5. **Açıklama:** Dosyayı oluşturduktan sonra, bu widget/screen'in nasıl kullanılacağına dair bana kısa bir örnek göster.