# Teqlif Mobile — Build Komutları
#
# Geliştirme:
#   make run-debugMode-in-stagingEnv            → debug mode + staging env
#   make run-debugMode-in-stagingEnv DEVICE=ios → aynısı, iPhone'a zorla
#   make run-debugMode-in-prodEnv               → debug mode + prod env
#   make run-releaseMode-in-stagingEnv          → release mode + staging env
#   make run-releaseMode-in-prodEnv             → release mode + prod env
#
#   DEVICE seçenekleri: ios | android | <cihaz-id>
#   Boş bırakılırsa Flutter bağlı cihazı sorar.
#
# Dağıtım:
#   make android-release   → Play Store AAB
#   make android-apk       → Play Store APK
#   make ios-release       → App Store IPA
#   make clean             → Build cache temizle

DEBUG_INFO_ANDROID := build/debug-info/android
DEBUG_INFO_IOS     := build/debug-info/ios

# Hedef cihaz — boş bırakılırsa Flutter sorar
DEVICE ?=
_D = $(if $(DEVICE),-d $(DEVICE),)

.PHONY: android-release ios-release android-apk clean \
        run-debugMode-in-stagingEnv run-debugMode-in-prodEnv \
        run-releaseMode-in-stagingEnv run-releaseMode-in-prodEnv

# Android logcat gürültüsünü bastır (iOS'ta sessizce atlanır)
define SUPPRESS
	@adb shell setprop log.tag.IMGMapper SUPPRESS 2>/dev/null || true
endef
define PREP
	flutter clean && flutter pub get
endef

## debug mode + staging env  (hot reload, staging API)
run-debugMode-in-stagingEnv:
	$(SUPPRESS)
	$(PREP) && flutter run $(_D) --dart-define-from-file=dart_defines/staging.json

## debug mode + prod env  (hot reload, production API)
run-debugMode-in-prodEnv:
	$(SUPPRESS)
	$(PREP) && flutter run $(_D) --dart-define-from-file=dart_defines/release.json

## release mode + staging env
run-releaseMode-in-stagingEnv:
	$(SUPPRESS)
	$(PREP) && flutter run $(_D) --release --dart-define-from-file=dart_defines/staging.json

## release mode + prod env
run-releaseMode-in-prodEnv:
	$(SUPPRESS)
	$(PREP) && flutter run $(_D) --release --dart-define-from-file=dart_defines/release.json

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
