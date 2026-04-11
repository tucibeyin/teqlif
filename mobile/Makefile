# Teqlif Mobile — Build Komutları
#
# Kullanım:
#   make android-release   → Play Store APK/AAB
#   make ios-release       → App Store IPA
#   make clean             → Build cache temizle
#
# Obfuscation hakkında:
#   --obfuscate              : Dart sembol isimlerini karıştırır (reverse engineering önler)
#   --split-debug-info=PATH  : Debug sembollerini ayrı dosyaya yazar (Sentry crash symbolication için gerekli)
#   Debug sembol dosyalarını (*.symbols) güvenli bir yerde saklayın — Sentry'e yüklenecek.

DEBUG_INFO_ANDROID := build/debug-info/android
DEBUG_INFO_IOS     := build/debug-info/ios

.PHONY: android-release ios-release android-apk clean

## Play Store — App Bundle (önerilen)
android-release:
	flutter build appbundle \
		--release \
		--obfuscate \
		--split-debug-info=$(DEBUG_INFO_ANDROID)
	dart run sentry_dart_plugin
	@echo "✓ AAB: build/app/outputs/bundle/release/app-release.aab"
	@echo "✓ Debug symbols Sentry'ye yüklendi"

## Play Store — APK (direkt dağıtım için)
android-apk:
	flutter build apk \
		--release \
		--obfuscate \
		--split-debug-info=$(DEBUG_INFO_ANDROID)
	@echo "✓ APK: build/app/outputs/flutter-apk/app-release.apk"

## App Store — IPA
ios-release:
	flutter build ios \
		--release \
		--obfuscate \
		--split-debug-info=$(DEBUG_INFO_IOS)
	dart run sentry_dart_plugin
	@echo "✓ iOS build tamamlandı: build/ios/iphoneos/"
	@echo "✓ Debug symbols Sentry'ye yüklendi"

clean:
	flutter clean
	rm -rf $(DEBUG_INFO_ANDROID) $(DEBUG_INFO_IOS)
