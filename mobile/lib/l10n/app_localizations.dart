import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @appName.
  ///
  /// In tr, this message translates to:
  /// **'teqlif'**
  String get appName;

  /// No description provided for @navLive.
  ///
  /// In tr, this message translates to:
  /// **'Canlı'**
  String get navLive;

  /// No description provided for @navListings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlar'**
  String get navListings;

  /// No description provided for @navSearch.
  ///
  /// In tr, this message translates to:
  /// **'Ara'**
  String get navSearch;

  /// No description provided for @navMessages.
  ///
  /// In tr, this message translates to:
  /// **'Mesajlar'**
  String get navMessages;

  /// No description provided for @navProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profilim'**
  String get navProfile;

  /// No description provided for @navSettings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get navSettings;

  /// No description provided for @loginWelcome.
  ///
  /// In tr, this message translates to:
  /// **'Hoş geldin'**
  String get loginWelcome;

  /// No description provided for @loginSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesabına giriş yap'**
  String get loginSubtitle;

  /// No description provided for @loginNoAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın yok mu? '**
  String get loginNoAccount;

  /// No description provided for @loginRegisterLink.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt ol'**
  String get loginRegisterLink;

  /// No description provided for @loginFaceId.
  ///
  /// In tr, this message translates to:
  /// **'🔒 Face ID ile Giriş'**
  String get loginFaceId;

  /// No description provided for @loginFaceIdDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bir sonraki girişinizde şifre yazmadan Face ID ile hızlıca giriş yapabilirsiniz.'**
  String get loginFaceIdDesc;

  /// No description provided for @registerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt Ol'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesap oluştur'**
  String get registerSubtitle;

  /// No description provided for @registerJoin.
  ///
  /// In tr, this message translates to:
  /// **'teqlif\'e katıl'**
  String get registerJoin;

  /// No description provided for @registerHaveAccount.
  ///
  /// In tr, this message translates to:
  /// **'Zaten hesabın var mı? '**
  String get registerHaveAccount;

  /// No description provided for @registerLoginLink.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yap'**
  String get registerLoginLink;

  /// No description provided for @fieldEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get fieldEmail;

  /// No description provided for @fieldEmailHint.
  ///
  /// In tr, this message translates to:
  /// **'E-posta giriniz'**
  String get fieldEmailHint;

  /// No description provided for @fieldPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get fieldPassword;

  /// No description provided for @fieldPasswordHint.
  ///
  /// In tr, this message translates to:
  /// **'Şifre giriniz'**
  String get fieldPasswordHint;

  /// No description provided for @fieldPasswordConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Şifre Tekrar'**
  String get fieldPasswordConfirm;

  /// No description provided for @fieldPasswordConfirmHint.
  ///
  /// In tr, this message translates to:
  /// **'Onaylamak için şifrenizi girin'**
  String get fieldPasswordConfirmHint;

  /// No description provided for @validPasswordMismatch.
  ///
  /// In tr, this message translates to:
  /// **'Şifreler eşleşmiyor'**
  String get validPasswordMismatch;

  /// No description provided for @fieldFullName.
  ///
  /// In tr, this message translates to:
  /// **'Ad Soyad'**
  String get fieldFullName;

  /// No description provided for @fieldFullNameHint.
  ///
  /// In tr, this message translates to:
  /// **'Ad soyad giriniz'**
  String get fieldFullNameHint;

  /// No description provided for @fieldUsername.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı Adı'**
  String get fieldUsername;

  /// No description provided for @fieldUsernameHint.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı giriniz'**
  String get fieldUsernameHint;

  /// No description provided for @fieldUsernameSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Küçük harf, rakam ve _ kullanılabilir'**
  String get fieldUsernameSubtitle;

  /// No description provided for @fieldCurrentPassword.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Şifre'**
  String get fieldCurrentPassword;

  /// No description provided for @fieldNewPassword.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre'**
  String get fieldNewPassword;

  /// No description provided for @fieldNewPasswordConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre (Tekrar)'**
  String get fieldNewPasswordConfirm;

  /// No description provided for @fieldEmailCode.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Doğrulama Kodu'**
  String get fieldEmailCode;

  /// No description provided for @fieldListingTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlan Başlığı'**
  String get fieldListingTitle;

  /// No description provided for @fieldListingTitleHint.
  ///
  /// In tr, this message translates to:
  /// **'Başlık giriniz'**
  String get fieldListingTitleHint;

  /// No description provided for @fieldCategory.
  ///
  /// In tr, this message translates to:
  /// **'Kategori'**
  String get fieldCategory;

  /// No description provided for @fieldCategoryHint.
  ///
  /// In tr, this message translates to:
  /// **'Kategori seçiniz'**
  String get fieldCategoryHint;

  /// No description provided for @fieldPrice.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat'**
  String get fieldPrice;

  /// No description provided for @fieldPriceHint.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat giriniz'**
  String get fieldPriceHint;

  /// No description provided for @fieldLocation.
  ///
  /// In tr, this message translates to:
  /// **'Konum (isteğe bağlı)'**
  String get fieldLocation;

  /// No description provided for @fieldLocationHint.
  ///
  /// In tr, this message translates to:
  /// **'Şehir seçin'**
  String get fieldLocationHint;

  /// No description provided for @fieldDescription.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama'**
  String get fieldDescription;

  /// No description provided for @fieldDescriptionHint.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama giriniz'**
  String get fieldDescriptionHint;

  /// No description provided for @fieldCity.
  ///
  /// In tr, this message translates to:
  /// **'Şehir'**
  String get fieldCity;

  /// No description provided for @btnLogin.
  ///
  /// In tr, this message translates to:
  /// **'Giriş Yap'**
  String get btnLogin;

  /// No description provided for @btnNotNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi Değil'**
  String get btnNotNow;

  /// No description provided for @btnEnable.
  ///
  /// In tr, this message translates to:
  /// **'Etkinleştir'**
  String get btnEnable;

  /// No description provided for @btnSave.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get btnSave;

  /// No description provided for @btnCancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get btnCancel;

  /// No description provided for @btnDelete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get btnDelete;

  /// No description provided for @btnDismiss.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get btnDismiss;

  /// No description provided for @btnRetry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar Dene'**
  String get btnRetry;

  /// No description provided for @btnLogout.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış Yap'**
  String get btnLogout;

  /// No description provided for @btnEditProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profili Düzenle'**
  String get btnEditProfile;

  /// No description provided for @btnCreateListing.
  ///
  /// In tr, this message translates to:
  /// **'İlan Ver'**
  String get btnCreateListing;

  /// No description provided for @btnPublishListing.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Yayınla'**
  String get btnPublishListing;

  /// No description provided for @btnSendCode.
  ///
  /// In tr, this message translates to:
  /// **'Kodu Gönder'**
  String get btnSendCode;

  /// No description provided for @btnChangePassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi Değiştir'**
  String get btnChangePassword;

  /// No description provided for @btnDeleteAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabı Sil'**
  String get btnDeleteAccount;

  /// No description provided for @btnAdd.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get btnAdd;

  /// No description provided for @btnAddPhoto.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf ekle'**
  String get btnAddPhoto;

  /// No description provided for @btnPickGallery.
  ///
  /// In tr, this message translates to:
  /// **'Galeriden Seç'**
  String get btnPickGallery;

  /// No description provided for @btnPickCamera.
  ///
  /// In tr, this message translates to:
  /// **'Kameradan Çek'**
  String get btnPickCamera;

  /// No description provided for @btnCamera.
  ///
  /// In tr, this message translates to:
  /// **'Kamera'**
  String get btnCamera;

  /// No description provided for @btnClearFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreleri Temizle'**
  String get btnClearFilters;

  /// No description provided for @btnDeactivate.
  ///
  /// In tr, this message translates to:
  /// **'Pasife Al'**
  String get btnDeactivate;

  /// No description provided for @btnActivate.
  ///
  /// In tr, this message translates to:
  /// **'Aktif Yap'**
  String get btnActivate;

  /// No description provided for @btnRemoveFavorite.
  ///
  /// In tr, this message translates to:
  /// **'Favoriden Çıkar'**
  String get btnRemoveFavorite;

  /// No description provided for @homeRecentListings.
  ///
  /// In tr, this message translates to:
  /// **'Son İlanlar'**
  String get homeRecentListings;

  /// No description provided for @searchHint.
  ///
  /// In tr, this message translates to:
  /// **'Aranıyor...'**
  String get searchHint;

  /// No description provided for @citySelectTitle.
  ///
  /// In tr, this message translates to:
  /// **'Şehir Seç'**
  String get citySelectTitle;

  /// No description provided for @cityAll.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Şehirler'**
  String get cityAll;

  /// No description provided for @catElectronics.
  ///
  /// In tr, this message translates to:
  /// **'Elektronik'**
  String get catElectronics;

  /// No description provided for @catVehicles.
  ///
  /// In tr, this message translates to:
  /// **'Vasıta'**
  String get catVehicles;

  /// No description provided for @catRealEstate.
  ///
  /// In tr, this message translates to:
  /// **'Emlak'**
  String get catRealEstate;

  /// No description provided for @catClothing.
  ///
  /// In tr, this message translates to:
  /// **'Giyim'**
  String get catClothing;

  /// No description provided for @catSports.
  ///
  /// In tr, this message translates to:
  /// **'Spor'**
  String get catSports;

  /// No description provided for @catBooks.
  ///
  /// In tr, this message translates to:
  /// **'Kitap'**
  String get catBooks;

  /// No description provided for @catHomeLife.
  ///
  /// In tr, this message translates to:
  /// **'Ev & Yaşam'**
  String get catHomeLife;

  /// No description provided for @catOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get catOther;

  /// No description provided for @profileUsername.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı'**
  String get profileUsername;

  /// No description provided for @profileListingCount.
  ///
  /// In tr, this message translates to:
  /// **'İlan'**
  String get profileListingCount;

  /// No description provided for @profileFollowers.
  ///
  /// In tr, this message translates to:
  /// **'Takipçi'**
  String get profileFollowers;

  /// No description provided for @profileFollowing.
  ///
  /// In tr, this message translates to:
  /// **'Takip'**
  String get profileFollowing;

  /// No description provided for @profileFollowersList.
  ///
  /// In tr, this message translates to:
  /// **'Takipçiler'**
  String get profileFollowersList;

  /// No description provided for @profileFollowingList.
  ///
  /// In tr, this message translates to:
  /// **'Takip Edilenler'**
  String get profileFollowingList;

  /// No description provided for @profileFirstListing.
  ///
  /// In tr, this message translates to:
  /// **'İlk ilanını ver!'**
  String get profileFirstListing;

  /// No description provided for @profileMyListings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarım'**
  String get profileMyListings;

  /// No description provided for @profileActiveListings.
  ///
  /// In tr, this message translates to:
  /// **'Aktif İlanlarım'**
  String get profileActiveListings;

  /// No description provided for @profilePassiveListings.
  ///
  /// In tr, this message translates to:
  /// **'Pasif İlanlarım'**
  String get profilePassiveListings;

  /// No description provided for @profileFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilerim'**
  String get profileFavorites;

  /// No description provided for @profileAccountSection.
  ///
  /// In tr, this message translates to:
  /// **'Hesap'**
  String get profileAccountSection;

  /// No description provided for @profileNotificationSettings.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim Ayarları'**
  String get profileNotificationSettings;

  /// No description provided for @profileBlockedUsers.
  ///
  /// In tr, this message translates to:
  /// **'Engellenen Kullanıcılar'**
  String get profileBlockedUsers;

  /// No description provided for @profileFaceId.
  ///
  /// In tr, this message translates to:
  /// **'Face ID ile Giriş'**
  String get profileFaceId;

  /// No description provided for @profileDarkMode.
  ///
  /// In tr, this message translates to:
  /// **'Karanlık Mod'**
  String get profileDarkMode;

  /// No description provided for @profileSupportSection.
  ///
  /// In tr, this message translates to:
  /// **'Destek'**
  String get profileSupportSection;

  /// No description provided for @profileSupportCenter.
  ///
  /// In tr, this message translates to:
  /// **'Destek Merkezi'**
  String get profileSupportCenter;

  /// No description provided for @profileTerms.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Şartları & EULA'**
  String get profileTerms;

  /// No description provided for @profilePrivacy.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik Politikası'**
  String get profilePrivacy;

  /// No description provided for @profileChangePassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifre Değiştir'**
  String get profileChangePassword;

  /// No description provided for @profileDeleteAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabı Kalıcı Olarak Sil'**
  String get profileDeleteAccount;

  /// No description provided for @profileDeleteAccountDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem geri alınamaz. Tüm verileriniz 30 gün içinde kalıcı olarak silinecektir.'**
  String get profileDeleteAccountDesc;

  /// No description provided for @sectionPhotos.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraflar'**
  String get sectionPhotos;

  /// No description provided for @photoCover.
  ///
  /// In tr, this message translates to:
  /// **'Kapak'**
  String get photoCover;

  /// No description provided for @listingMaxPhotos.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 10 fotoğraf ekleyebilirsiniz'**
  String get listingMaxPhotos;

  /// No description provided for @statusOn.
  ///
  /// In tr, this message translates to:
  /// **'Açık'**
  String get statusOn;

  /// No description provided for @statusOff.
  ///
  /// In tr, this message translates to:
  /// **'Kapalı'**
  String get statusOff;

  /// No description provided for @notifSettingsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim Ayarları'**
  String get notifSettingsTitle;

  /// No description provided for @notifMessagesTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mesajlar'**
  String get notifMessagesTitle;

  /// No description provided for @notifMessagesDesc.
  ///
  /// In tr, this message translates to:
  /// **'Yeni direkt mesaj geldiğinde'**
  String get notifMessagesDesc;

  /// No description provided for @notifNewFollowerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Takipçi'**
  String get notifNewFollowerTitle;

  /// No description provided for @notifNewFollowerDesc.
  ///
  /// In tr, this message translates to:
  /// **'Biri seni takip ettiğinde'**
  String get notifNewFollowerDesc;

  /// No description provided for @notifAuctionWonTitle.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırma Kazandı'**
  String get notifAuctionWonTitle;

  /// No description provided for @notifAuctionWonDesc.
  ///
  /// In tr, this message translates to:
  /// **'Teklifin kabul edildiğinde'**
  String get notifAuctionWonDesc;

  /// No description provided for @notifLiveStreamTitle.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayın'**
  String get notifLiveStreamTitle;

  /// No description provided for @notifLiveStreamDesc.
  ///
  /// In tr, this message translates to:
  /// **'Takip ettiğin biri yayın açtığında'**
  String get notifLiveStreamDesc;

  /// No description provided for @notifNewListingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni İlan'**
  String get notifNewListingTitle;

  /// No description provided for @notifNewListingDesc.
  ///
  /// In tr, this message translates to:
  /// **'Takip ettiğin biri ilan eklediğinde'**
  String get notifNewListingDesc;

  /// No description provided for @notifNewBidTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Teklif'**
  String get notifNewBidTitle;

  /// No description provided for @notifNewBidDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanına teklif geldiğinde'**
  String get notifNewBidDesc;

  /// No description provided for @notifBidOutbidTitle.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Geçildi'**
  String get notifBidOutbidTitle;

  /// No description provided for @notifBidOutbidDesc.
  ///
  /// In tr, this message translates to:
  /// **'Açık artırmada teklifin geçildiğinde'**
  String get notifBidOutbidDesc;

  /// No description provided for @validFullNameMin.
  ///
  /// In tr, this message translates to:
  /// **'Ad soyad en az 2 karakter olmalı'**
  String get validFullNameMin;

  /// No description provided for @validFullNameMax.
  ///
  /// In tr, this message translates to:
  /// **'Ad soyad en fazla 100 karakter olmalı'**
  String get validFullNameMax;

  /// No description provided for @validUsernameMin.
  ///
  /// In tr, this message translates to:
  /// **'En az 3 karakter olmalı'**
  String get validUsernameMin;

  /// No description provided for @validUsernameMax.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 50 karakter olmalı'**
  String get validUsernameMax;

  /// No description provided for @validUsernameChars.
  ///
  /// In tr, this message translates to:
  /// **'Sadece küçük harf, rakam ve _ kullanılabilir'**
  String get validUsernameChars;

  /// No description provided for @validUsernameTaken.
  ///
  /// In tr, this message translates to:
  /// **'Bu kullanıcı adı zaten alınmış'**
  String get validUsernameTaken;

  /// No description provided for @validUsernameInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı geçersiz. Sadece küçük harf, rakam ve _ kullanılabilir.'**
  String get validUsernameInvalid;

  /// No description provided for @validEmailMax.
  ///
  /// In tr, this message translates to:
  /// **'E-posta en fazla 255 karakter olmalı'**
  String get validEmailMax;

  /// No description provided for @validEmailInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir e-posta adresi giriniz'**
  String get validEmailInvalid;

  /// No description provided for @validPasswordMin.
  ///
  /// In tr, this message translates to:
  /// **'En az 8 karakter olmalı'**
  String get validPasswordMin;

  /// No description provided for @validNewPasswordMin.
  ///
  /// In tr, this message translates to:
  /// **'Yeni şifre en az 8 karakter olmalı.'**
  String get validNewPasswordMin;

  /// No description provided for @validPasswordsMatch.
  ///
  /// In tr, this message translates to:
  /// **'Yeni şifreler eşleşmiyor.'**
  String get validPasswordsMatch;

  /// No description provided for @validVerificationCode.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodunu girin.'**
  String get validVerificationCode;

  /// No description provided for @validAllFields.
  ///
  /// In tr, this message translates to:
  /// **'Tüm alanları doldurun.'**
  String get validAllFields;

  /// No description provided for @validTermsRequired.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Şartları\'nı kabul etmelisiniz.'**
  String get validTermsRequired;

  /// No description provided for @usernameChecking.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı kontrol ediliyor...'**
  String get usernameChecking;

  /// No description provided for @usernameCheckingWait.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı kontrol ediliyor, lütfen bekleyin...'**
  String get usernameCheckingWait;

  /// No description provided for @fieldPhone.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Numarası (İsteğe Bağlı)'**
  String get fieldPhone;

  /// No description provided for @fieldPhoneHint.
  ///
  /// In tr, this message translates to:
  /// **'0### ### ## ##'**
  String get fieldPhoneHint;

  /// No description provided for @emptyListings.
  ///
  /// In tr, this message translates to:
  /// **'Henüz ilan yok'**
  String get emptyListings;

  /// No description provided for @emptyFilteredListings.
  ///
  /// In tr, this message translates to:
  /// **'Bu filtreyle ilan bulunamadı'**
  String get emptyFilteredListings;

  /// No description provided for @emptyActiveListings.
  ///
  /// In tr, this message translates to:
  /// **'Aktif ilan yok'**
  String get emptyActiveListings;

  /// No description provided for @emptyPassiveListings.
  ///
  /// In tr, this message translates to:
  /// **'Pasif ilan yok'**
  String get emptyPassiveListings;

  /// No description provided for @emptyFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Henüz favori ilan yok'**
  String get emptyFavorites;

  /// No description provided for @errorConnection.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı hatası'**
  String get errorConnection;

  /// No description provided for @errorListingsLoad.
  ///
  /// In tr, this message translates to:
  /// **'İlanlar yüklenemedi'**
  String get errorListingsLoad;

  /// No description provided for @errorPhotoUpload.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf yüklenemedi. Tekrar deneyin.'**
  String get errorPhotoUpload;

  /// No description provided for @errorCaptchaFailed.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik doğrulaması başarısız. Lütfen tekrar deneyin.'**
  String get errorCaptchaFailed;

  /// No description provided for @errorTooFast.
  ///
  /// In tr, this message translates to:
  /// **'Çok hızlı işlem yapıyorsunuz. Lütfen biraz bekleyin.'**
  String get errorTooFast;

  /// No description provided for @msgPasswordChanged.
  ///
  /// In tr, this message translates to:
  /// **'Şifreniz başarıyla değiştirildi.'**
  String get msgPasswordChanged;

  /// No description provided for @msgListingPublished.
  ///
  /// In tr, this message translates to:
  /// **'İlan yayına alındı!'**
  String get msgListingPublished;

  /// No description provided for @dialogDeleteListingTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Sil'**
  String get dialogDeleteListingTitle;

  /// No description provided for @dialogDeleteListingDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu ilanı kalıcı olarak silmek istiyor musunuz?'**
  String get dialogDeleteListingDesc;

  /// No description provided for @dialogFaceIdActivateTitle.
  ///
  /// In tr, this message translates to:
  /// **'Face ID\'yi etkinleştirmek için doğrulayın'**
  String get dialogFaceIdActivateTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get settingsLanguage;

  /// No description provided for @homeAppBarTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlanlar'**
  String get homeAppBarTitle;

  /// No description provided for @homeSearchingHeader.
  ///
  /// In tr, this message translates to:
  /// **'Aranıyor...'**
  String get homeSearchingHeader;

  /// No description provided for @homeResultsCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} ilan bulundu'**
  String homeResultsCount(int count);

  /// No description provided for @searchUserHint.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı ara...'**
  String get searchUserHint;

  /// No description provided for @searchNoUser.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı bulunamadı'**
  String get searchNoUser;

  /// No description provided for @searchLiveStreams.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayınlar'**
  String get searchLiveStreams;

  /// No description provided for @searchNoContent.
  ///
  /// In tr, this message translates to:
  /// **'Henüz içerik yok'**
  String get searchNoContent;

  /// No description provided for @msgTabMessages.
  ///
  /// In tr, this message translates to:
  /// **'Mesajlar'**
  String get msgTabMessages;

  /// No description provided for @msgTabNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler'**
  String get msgTabNotifications;

  /// No description provided for @msgNoMessages.
  ///
  /// In tr, this message translates to:
  /// **'Henüz mesajın yok'**
  String get msgNoMessages;

  /// No description provided for @msgNoMessagesDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bir ilanla ilgilendiğinde\nburada görüntülenecek'**
  String get msgNoMessagesDesc;

  /// No description provided for @msgSendFailed.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj gönderilemedi'**
  String get msgSendFailed;

  /// No description provided for @msgWriteHint.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj yaz...'**
  String get msgWriteHint;

  /// No description provided for @msgNoChat.
  ///
  /// In tr, this message translates to:
  /// **'Henüz mesaj yok.\nİlk mesajı gönder!'**
  String get msgNoChat;

  /// No description provided for @msgGoToListing.
  ///
  /// In tr, this message translates to:
  /// **'📌 İlana Git'**
  String get msgGoToListing;

  /// No description provided for @notifNone.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim yok'**
  String get notifNone;

  /// No description provided for @notifNoneDesc.
  ///
  /// In tr, this message translates to:
  /// **'Yeni bildirimler burada görünecek'**
  String get notifNoneDesc;

  /// No description provided for @notificationsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler'**
  String get notificationsTitle;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü oku'**
  String get notificationsMarkAllRead;

  /// No description provided for @blockedUsersTitle.
  ///
  /// In tr, this message translates to:
  /// **'Engellenen Kullanıcılar'**
  String get blockedUsersTitle;

  /// No description provided for @blockedNone.
  ///
  /// In tr, this message translates to:
  /// **'Engellenen kullanıcı yok'**
  String get blockedNone;

  /// No description provided for @blockedUnblock.
  ///
  /// In tr, this message translates to:
  /// **'Engeli Kaldır'**
  String get blockedUnblock;

  /// No description provided for @blockedActionFailed.
  ///
  /// In tr, this message translates to:
  /// **'İşlem gerçekleştirilemedi'**
  String get blockedActionFailed;

  /// No description provided for @followNoFollowers.
  ///
  /// In tr, this message translates to:
  /// **'Henüz takipçi yok'**
  String get followNoFollowers;

  /// No description provided for @followNoFollowing.
  ///
  /// In tr, this message translates to:
  /// **'Henüz takip edilen yok'**
  String get followNoFollowing;

  /// No description provided for @followBtnFollowing.
  ///
  /// In tr, this message translates to:
  /// **'Takiptesin'**
  String get followBtnFollowing;

  /// No description provided for @followBtnFollow.
  ///
  /// In tr, this message translates to:
  /// **'Takip Et'**
  String get followBtnFollow;

  /// No description provided for @pubProfileUserNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı bulunamadı'**
  String get pubProfileUserNotFound;

  /// No description provided for @pubProfileListingsCount.
  ///
  /// In tr, this message translates to:
  /// **'İlanları ({count})'**
  String pubProfileListingsCount(int count);

  /// No description provided for @pubProfileStatListings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlar'**
  String get pubProfileStatListings;

  /// No description provided for @pubProfileStatFollowers.
  ///
  /// In tr, this message translates to:
  /// **'Takipçi'**
  String get pubProfileStatFollowers;

  /// No description provided for @pubProfileStatFollowing.
  ///
  /// In tr, this message translates to:
  /// **'Takip'**
  String get pubProfileStatFollowing;

  /// No description provided for @pubProfileEditComingSoon.
  ///
  /// In tr, this message translates to:
  /// **'Profil düzenleme yakında'**
  String get pubProfileEditComingSoon;

  /// No description provided for @pubProfileFollowingLabel.
  ///
  /// In tr, this message translates to:
  /// **'Takip Ediliyor'**
  String get pubProfileFollowingLabel;

  /// No description provided for @pubProfileFollowLabel.
  ///
  /// In tr, this message translates to:
  /// **'Takip Et'**
  String get pubProfileFollowLabel;

  /// No description provided for @pubProfileSendMessage.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj Gönder'**
  String get pubProfileSendMessage;

  /// No description provided for @pubProfileUpdateRating.
  ///
  /// In tr, this message translates to:
  /// **'Puanı Güncelle'**
  String get pubProfileUpdateRating;

  /// No description provided for @pubProfileGiveRating.
  ///
  /// In tr, this message translates to:
  /// **'Puan Ver'**
  String get pubProfileGiveRating;

  /// No description provided for @pubProfileBlock.
  ///
  /// In tr, this message translates to:
  /// **'Engelle'**
  String get pubProfileBlock;

  /// No description provided for @pubProfileUnblock.
  ///
  /// In tr, this message translates to:
  /// **'Engeli Kaldır'**
  String get pubProfileUnblock;

  /// No description provided for @pubProfileActionFailed.
  ///
  /// In tr, this message translates to:
  /// **'İşlem gerçekleştirilemedi'**
  String get pubProfileActionFailed;

  /// No description provided for @pubProfileNoReview.
  ///
  /// In tr, this message translates to:
  /// **'Henüz değerlendirme yok'**
  String get pubProfileNoReview;

  /// No description provided for @ratingVeryBad.
  ///
  /// In tr, this message translates to:
  /// **'Çok kötü'**
  String get ratingVeryBad;

  /// No description provided for @ratingBad.
  ///
  /// In tr, this message translates to:
  /// **'Kötü'**
  String get ratingBad;

  /// No description provided for @ratingMedium.
  ///
  /// In tr, this message translates to:
  /// **'Orta'**
  String get ratingMedium;

  /// No description provided for @ratingGood.
  ///
  /// In tr, this message translates to:
  /// **'İyi'**
  String get ratingGood;

  /// No description provided for @ratingExcellent.
  ///
  /// In tr, this message translates to:
  /// **'Mükemmel'**
  String get ratingExcellent;

  /// No description provided for @ratingSelectStar.
  ///
  /// In tr, this message translates to:
  /// **'Bir yıldız seçin'**
  String get ratingSelectStar;

  /// No description provided for @ratingCommentHint.
  ///
  /// In tr, this message translates to:
  /// **'Neden bu puanı veriyorsunuz? (isteğe bağlı)'**
  String get ratingCommentHint;

  /// No description provided for @ratingSaveFailed.
  ///
  /// In tr, this message translates to:
  /// **'Puan kaydedilemedi'**
  String get ratingSaveFailed;

  /// No description provided for @ratingReviews.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendirmeler'**
  String get ratingReviews;

  /// No description provided for @ratingCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} değerlendirme'**
  String ratingCount(int count);

  /// No description provided for @ratingStarCount.
  ///
  /// In tr, this message translates to:
  /// **'({count} puan)'**
  String ratingStarCount(int count);

  /// No description provided for @createListingPhotoCount.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraflar ({count}/{max})'**
  String createListingPhotoCount(int count, int max);

  /// No description provided for @createListingSelectOption.
  ///
  /// In tr, this message translates to:
  /// **'-- Seçiniz --'**
  String get createListingSelectOption;

  /// No description provided for @createListingPhotoUploadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf yüklenemedi: {error}'**
  String createListingPhotoUploadFailed(String error);

  /// No description provided for @createListingConnError.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı hatası. Lütfen tekrar deneyin.'**
  String get createListingConnError;

  /// No description provided for @notifSettingsMessagesTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mesajlar'**
  String get notifSettingsMessagesTitle;

  /// No description provided for @notifSettingsMessagesDesc.
  ///
  /// In tr, this message translates to:
  /// **'Yeni direkt mesaj geldiğinde'**
  String get notifSettingsMessagesDesc;

  /// No description provided for @notifSettingsFollowsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Takipçi'**
  String get notifSettingsFollowsTitle;

  /// No description provided for @notifSettingsFollowsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Biri seni takip ettiğinde'**
  String get notifSettingsFollowsDesc;

  /// No description provided for @notifSettingsAuctionWonTitle.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırma Kazandı'**
  String get notifSettingsAuctionWonTitle;

  /// No description provided for @notifSettingsAuctionWonDesc.
  ///
  /// In tr, this message translates to:
  /// **'Teklifin kabul edildiğinde'**
  String get notifSettingsAuctionWonDesc;

  /// No description provided for @notifSettingsStreamStartedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayın'**
  String get notifSettingsStreamStartedTitle;

  /// No description provided for @notifSettingsStreamStartedDesc.
  ///
  /// In tr, this message translates to:
  /// **'Takip ettiğin biri yayın açtığında'**
  String get notifSettingsStreamStartedDesc;

  /// No description provided for @notifSettingsNewListingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni İlan'**
  String get notifSettingsNewListingTitle;

  /// No description provided for @notifSettingsNewListingDesc.
  ///
  /// In tr, this message translates to:
  /// **'Takip ettiğin biri ilan eklediğinde'**
  String get notifSettingsNewListingDesc;

  /// No description provided for @notifSettingsNewBidTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Teklif'**
  String get notifSettingsNewBidTitle;

  /// No description provided for @notifSettingsNewBidDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanına teklif geldiğinde'**
  String get notifSettingsNewBidDesc;

  /// No description provided for @notifSettingsOutbidTitle.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Geçildi'**
  String get notifSettingsOutbidTitle;

  /// No description provided for @notifSettingsOutbidDesc.
  ///
  /// In tr, this message translates to:
  /// **'Açık artırmada teklifin geçildiğinde'**
  String get notifSettingsOutbidDesc;

  /// No description provided for @btnOk.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get btnOk;

  /// No description provided for @btnGoBack.
  ///
  /// In tr, this message translates to:
  /// **'Geri Dön'**
  String get btnGoBack;

  /// No description provided for @errorGeneric.
  ///
  /// In tr, this message translates to:
  /// **'Bir hata oluştu'**
  String get errorGeneric;

  /// No description provided for @listingPriceNotSet.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Belirtilmemiş'**
  String get listingPriceNotSet;

  /// No description provided for @listingMsgLoginRequired.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj göndermek için giriş yapmalısınız'**
  String get listingMsgLoginRequired;

  /// No description provided for @listingMsgOwnListing.
  ///
  /// In tr, this message translates to:
  /// **'Kendi ilanınıza mesaj gönderemezsiniz'**
  String get listingMsgOwnListing;

  /// No description provided for @listingActivated.
  ///
  /// In tr, this message translates to:
  /// **'İlan aktif yapıldı'**
  String get listingActivated;

  /// No description provided for @listingDeactivated.
  ///
  /// In tr, this message translates to:
  /// **'İlan pasife alındı'**
  String get listingDeactivated;

  /// No description provided for @listingDeleteConfirmContent.
  ///
  /// In tr, this message translates to:
  /// **'Bu ilanı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'**
  String get listingDeleteConfirmContent;

  /// No description provided for @listingDeleteConfirmYes.
  ///
  /// In tr, this message translates to:
  /// **'Evet, Sil'**
  String get listingDeleteConfirmYes;

  /// No description provided for @listingInfo.
  ///
  /// In tr, this message translates to:
  /// **'İlan Bilgileri'**
  String get listingInfo;

  /// No description provided for @listingLocationLabel.
  ///
  /// In tr, this message translates to:
  /// **'Konum'**
  String get listingLocationLabel;

  /// No description provided for @listingSendMessage.
  ///
  /// In tr, this message translates to:
  /// **'Satıcıya Mesaj Gönder'**
  String get listingSendMessage;

  /// No description provided for @listingReportTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Şikayet Et'**
  String get listingReportTooltip;

  /// No description provided for @listingDeleteTooltip.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Sil'**
  String get listingDeleteTooltip;

  /// No description provided for @listingReportTitle.
  ///
  /// In tr, this message translates to:
  /// **'🚩 İlanı Şikayet Et'**
  String get listingReportTitle;

  /// No description provided for @listingReportSelectHint.
  ///
  /// In tr, this message translates to:
  /// **'Neden seçin'**
  String get listingReportSelectHint;

  /// No description provided for @listingReportMisleading.
  ///
  /// In tr, this message translates to:
  /// **'Yanıltıcı ilan'**
  String get listingReportMisleading;

  /// No description provided for @listingReportIllegal.
  ///
  /// In tr, this message translates to:
  /// **'Yasadışı ürün'**
  String get listingReportIllegal;

  /// No description provided for @listingReportSpam.
  ///
  /// In tr, this message translates to:
  /// **'Spam / tekrar ilan'**
  String get listingReportSpam;

  /// No description provided for @listingReportInappropriate.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz içerik'**
  String get listingReportInappropriate;

  /// No description provided for @listingReportFraud.
  ///
  /// In tr, this message translates to:
  /// **'Dolandırıcılık şüphesi'**
  String get listingReportFraud;

  /// No description provided for @listingReportNoteHint.
  ///
  /// In tr, this message translates to:
  /// **'Ek açıklama (isteğe bağlı)'**
  String get listingReportNoteHint;

  /// No description provided for @listingReportSubmitBtn.
  ///
  /// In tr, this message translates to:
  /// **'Şikayeti Gönder'**
  String get listingReportSubmitBtn;

  /// No description provided for @listingReportSelectRequired.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir neden seçin'**
  String get listingReportSelectRequired;

  /// No description provided for @listingReportSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Şikayetiniz alındı. Teşekkür ederiz.'**
  String get listingReportSuccess;

  /// No description provided for @listingDescriptionLabel.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama'**
  String get listingDescriptionLabel;

  /// No description provided for @liveStreamsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayınlar'**
  String get liveStreamsTitle;

  /// No description provided for @liveStartStream.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Aç'**
  String get liveStartStream;

  /// No description provided for @liveAllCategory.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get liveAllCategory;

  /// No description provided for @liveNoStreams.
  ///
  /// In tr, this message translates to:
  /// **'Şu an aktif yayın yok'**
  String get liveNoStreams;

  /// No description provided for @liveBeFirst.
  ///
  /// In tr, this message translates to:
  /// **'İlk yayını sen başlat!'**
  String get liveBeFirst;

  /// No description provided for @livePullToRefresh.
  ///
  /// In tr, this message translates to:
  /// **'Yenilemek için aşağı çekin'**
  String get livePullToRefresh;

  /// No description provided for @liveStreamsLoadError.
  ///
  /// In tr, this message translates to:
  /// **'Yayınlar yüklenemedi'**
  String get liveStreamsLoadError;

  /// No description provided for @liveStartStreamDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Başlat'**
  String get liveStartStreamDialogTitle;

  /// No description provided for @liveStreamTitleHint.
  ///
  /// In tr, this message translates to:
  /// **'Yayın başlığı'**
  String get liveStreamTitleHint;

  /// No description provided for @liveStreamTitleLabel.
  ///
  /// In tr, this message translates to:
  /// **'Başlık *'**
  String get liveStreamTitleLabel;

  /// No description provided for @liveCategoryLabel.
  ///
  /// In tr, this message translates to:
  /// **'Kategori *'**
  String get liveCategoryLabel;

  /// No description provided for @liveCategoryHint.
  ///
  /// In tr, this message translates to:
  /// **'Kategori seç'**
  String get liveCategoryHint;

  /// No description provided for @liveStartBtn.
  ///
  /// In tr, this message translates to:
  /// **'Başlat'**
  String get liveStartBtn;

  /// No description provided for @liveStreamTitleRequired.
  ///
  /// In tr, this message translates to:
  /// **'Yayın başlığı zorunludur'**
  String get liveStreamTitleRequired;

  /// No description provided for @liveStreamTitleMin.
  ///
  /// In tr, this message translates to:
  /// **'Yayın başlığı 3 karakterden fazla olmalı.'**
  String get liveStreamTitleMin;

  /// No description provided for @liveCategoryRequired.
  ///
  /// In tr, this message translates to:
  /// **'Kategori seçimi zorunludur'**
  String get liveCategoryRequired;

  /// No description provided for @liveLoginRequired.
  ///
  /// In tr, this message translates to:
  /// **'Yayın başlatmak için giriş yapmalısınız'**
  String get liveLoginRequired;

  /// No description provided for @liveBadgeLabel.
  ///
  /// In tr, this message translates to:
  /// **'CANLI'**
  String get liveBadgeLabel;

  /// No description provided for @liveEndedBadge.
  ///
  /// In tr, this message translates to:
  /// **'BİTTİ'**
  String get liveEndedBadge;

  /// No description provided for @liveConnecting.
  ///
  /// In tr, this message translates to:
  /// **'Yayın başlatılıyor...'**
  String get liveConnecting;

  /// No description provided for @liveConnectingViewer.
  ///
  /// In tr, this message translates to:
  /// **'Yayına bağlanıyor...'**
  String get liveConnectingViewer;

  /// No description provided for @livePermissionRequired.
  ///
  /// In tr, this message translates to:
  /// **'Kamera ve mikrofon izni gerekli'**
  String get livePermissionRequired;

  /// No description provided for @liveViewersTitle.
  ///
  /// In tr, this message translates to:
  /// **'👁 İzleyiciler ({count})'**
  String liveViewersTitle(int count);

  /// No description provided for @liveNoViewers.
  ///
  /// In tr, this message translates to:
  /// **'Henüz izleyici yok'**
  String get liveNoViewers;

  /// No description provided for @liveEndStreamTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yayını Bitir'**
  String get liveEndStreamTitle;

  /// No description provided for @liveEndStreamConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Yayını sonlandırmak istiyor musunuz?'**
  String get liveEndStreamConfirm;

  /// No description provided for @liveEndStreamBtn.
  ///
  /// In tr, this message translates to:
  /// **'Bitir'**
  String get liveEndStreamBtn;

  /// No description provided for @liveGoBack.
  ///
  /// In tr, this message translates to:
  /// **'Geri Dön'**
  String get liveGoBack;

  /// No description provided for @liveEnded.
  ///
  /// In tr, this message translates to:
  /// **'Yayın sona erdi'**
  String get liveEnded;

  /// No description provided for @liveStreamEndedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Sona Erdi'**
  String get liveStreamEndedTitle;

  /// No description provided for @liveStreamEndedDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu yayın yayıncı tarafından sonlandırıldı.'**
  String get liveStreamEndedDesc;

  /// No description provided for @liveStreamEndedOverlay.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Sona Erdi'**
  String get liveStreamEndedOverlay;

  /// No description provided for @liveDiscoverStreams.
  ///
  /// In tr, this message translates to:
  /// **'Kaydırarak başka yayınları keşfet'**
  String get liveDiscoverStreams;

  /// No description provided for @liveLeaveBtn.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıl'**
  String get liveLeaveBtn;

  /// No description provided for @liveNextStream.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki yayın'**
  String get liveNextStream;

  /// No description provided for @liveCameraClosed.
  ///
  /// In tr, this message translates to:
  /// **'Kamera Kapalı'**
  String get liveCameraClosed;

  /// No description provided for @liveWaitingVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video bekleniyor...'**
  String get liveWaitingVideo;

  /// No description provided for @liveModDemotedSelf.
  ///
  /// In tr, this message translates to:
  /// **'Moderatörlüğünüz @{username} tarafından kaldırıldı.'**
  String liveModDemotedSelf(String username);

  /// No description provided for @liveModPromotedSelf.
  ///
  /// In tr, this message translates to:
  /// **'⭐ @{username} sizi moderatör yaptı! Artık izleyicileri yönetebilirsiniz.'**
  String liveModPromotedSelf(String username);

  /// No description provided for @modTitle.
  ///
  /// In tr, this message translates to:
  /// **'🛡 Moderasyon'**
  String get modTitle;

  /// No description provided for @modMute.
  ///
  /// In tr, this message translates to:
  /// **'Sustur'**
  String get modMute;

  /// No description provided for @modUnmute.
  ///
  /// In tr, this message translates to:
  /// **'Susturmayı Kaldır'**
  String get modUnmute;

  /// No description provided for @modPromote.
  ///
  /// In tr, this message translates to:
  /// **'Moderatör Yap'**
  String get modPromote;

  /// No description provided for @modDemote.
  ///
  /// In tr, this message translates to:
  /// **'Moderatörlüğü Kaldır'**
  String get modDemote;

  /// No description provided for @modKick.
  ///
  /// In tr, this message translates to:
  /// **'Yayından At'**
  String get modKick;

  /// No description provided for @modMutedMsg.
  ///
  /// In tr, this message translates to:
  /// **'@{username} susturuldu'**
  String modMutedMsg(String username);

  /// No description provided for @modUnmutedMsg.
  ///
  /// In tr, this message translates to:
  /// **'Susturma kaldırıldı'**
  String get modUnmutedMsg;

  /// No description provided for @modPromotedMsg.
  ///
  /// In tr, this message translates to:
  /// **'@{username} moderatör yapıldı'**
  String modPromotedMsg(String username);

  /// No description provided for @modDemotedMsg.
  ///
  /// In tr, this message translates to:
  /// **'@{username} moderatörlükten alındı'**
  String modDemotedMsg(String username);

  /// No description provided for @modKickedMsg.
  ///
  /// In tr, this message translates to:
  /// **'@{username} yayından atıldı'**
  String modKickedMsg(String username);

  /// No description provided for @modPromotedSnack.
  ///
  /// In tr, this message translates to:
  /// **'⭐ @{username} moderatör yapıldı!'**
  String modPromotedSnack(String username);

  /// No description provided for @modDemotedSnack.
  ///
  /// In tr, this message translates to:
  /// **'✖ @{username} moderatörlükten alındı'**
  String modDemotedSnack(String username);

  /// No description provided for @chatMessageHint.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj yaz...'**
  String get chatMessageHint;

  /// No description provided for @chatMutedHint.
  ///
  /// In tr, this message translates to:
  /// **'🔇 Susturuldunuz'**
  String get chatMutedHint;

  /// No description provided for @chatHistoryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sohbet Geçmişi'**
  String get chatHistoryTitle;

  /// No description provided for @chatHistoryCount.
  ///
  /// In tr, this message translates to:
  /// **'Son {count} mesaj'**
  String chatHistoryCount(int count);

  /// No description provided for @auctionTitle.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırma'**
  String get auctionTitle;

  /// No description provided for @auctionBidsHeader.
  ///
  /// In tr, this message translates to:
  /// **'TEKLİFLER'**
  String get auctionBidsHeader;

  /// No description provided for @auctionAcceptBidTitle.
  ///
  /// In tr, this message translates to:
  /// **'✅ Teklifi Kabul Et'**
  String get auctionAcceptBidTitle;

  /// No description provided for @auctionItem.
  ///
  /// In tr, this message translates to:
  /// **'Ürün'**
  String get auctionItem;

  /// No description provided for @auctionWinnerPrice.
  ///
  /// In tr, this message translates to:
  /// **'Kazanan Fiyat'**
  String get auctionWinnerPrice;

  /// No description provided for @auctionBidder.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Sahibi'**
  String get auctionBidder;

  /// No description provided for @auctionAcceptConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Kabul edildiğinde artırma kapanır ve özet sohbete otomatik mesaj gönderilir.'**
  String get auctionAcceptConfirm;

  /// No description provided for @auctionCancelBtn.
  ///
  /// In tr, this message translates to:
  /// **'İptal Et'**
  String get auctionCancelBtn;

  /// No description provided for @auctionContinueBtn.
  ///
  /// In tr, this message translates to:
  /// **'Devam Et'**
  String get auctionContinueBtn;

  /// No description provided for @auctionAccepted.
  ///
  /// In tr, this message translates to:
  /// **'Teklif kabul edildi! Özet sohbete gönderildi.'**
  String get auctionAccepted;

  /// No description provided for @auctionEndTitle.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırmayı Bitir'**
  String get auctionEndTitle;

  /// No description provided for @auctionEndDesc.
  ///
  /// In tr, this message translates to:
  /// **'Sonuç kaydedilecek ve artırma kapanacak.'**
  String get auctionEndDesc;

  /// No description provided for @auctionEndBtn.
  ///
  /// In tr, this message translates to:
  /// **'Bitir'**
  String get auctionEndBtn;

  /// No description provided for @auctionStatusActive.
  ///
  /// In tr, this message translates to:
  /// **'AKTİF'**
  String get auctionStatusActive;

  /// No description provided for @auctionStatusPending.
  ///
  /// In tr, this message translates to:
  /// **'ONAY BEKLİYOR ⚡'**
  String get auctionStatusPending;

  /// No description provided for @auctionStatusPaused.
  ///
  /// In tr, this message translates to:
  /// **'DURAKLADI'**
  String get auctionStatusPaused;

  /// No description provided for @auctionStatusSold.
  ///
  /// In tr, this message translates to:
  /// **'SATILDI 🛒'**
  String get auctionStatusSold;

  /// No description provided for @auctionStatusEnded.
  ///
  /// In tr, this message translates to:
  /// **'BİTTİ'**
  String get auctionStatusEnded;

  /// No description provided for @auctionStatusIdle.
  ///
  /// In tr, this message translates to:
  /// **'AÇIK ARTIRMA'**
  String get auctionStatusIdle;

  /// No description provided for @auctionStartBtn.
  ///
  /// In tr, this message translates to:
  /// **'▶ Başlat'**
  String get auctionStartBtn;

  /// No description provided for @auctionBidBtn.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Ver'**
  String get auctionBidBtn;

  /// No description provided for @auctionMutedBtn.
  ///
  /// In tr, this message translates to:
  /// **'🔇 Susturuldunuz'**
  String get auctionMutedBtn;

  /// No description provided for @auctionBuyNowTitle.
  ///
  /// In tr, this message translates to:
  /// **'⚡ Hemen Al'**
  String get auctionBuyNowTitle;

  /// No description provided for @auctionBuyNowPrice.
  ///
  /// In tr, this message translates to:
  /// **'Hemen Al Fiyatı'**
  String get auctionBuyNowPrice;

  /// No description provided for @auctionBuyNowConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Bu fiyatla ürünü hemen satın almak istiyor musun? Artırma sona erecek.'**
  String get auctionBuyNowConfirm;

  /// No description provided for @auctionBuyNowRequest.
  ///
  /// In tr, this message translates to:
  /// **'⚡ Hemen Al Talebi'**
  String get auctionBuyNowRequest;

  /// No description provided for @auctionBuyNowRequester.
  ///
  /// In tr, this message translates to:
  /// **'Talep Eden'**
  String get auctionBuyNowRequester;

  /// No description provided for @auctionBuyNowRequestConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Bu kişinin Hemen Al talebini onaylıyor musun?'**
  String get auctionBuyNowRequestConfirm;

  /// No description provided for @auctionBuyNowReject.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get auctionBuyNowReject;

  /// No description provided for @auctionBuyNowApprove.
  ///
  /// In tr, this message translates to:
  /// **'Onayla'**
  String get auctionBuyNowApprove;

  /// No description provided for @auctionWaitingHost.
  ///
  /// In tr, this message translates to:
  /// **'Host\'tan cevap bekleniyor'**
  String get auctionWaitingHost;

  /// No description provided for @auctionWaitingHostDesc.
  ///
  /// In tr, this message translates to:
  /// **'Host onayladığında satın alma tamamlanacak.'**
  String get auctionWaitingHostDesc;

  /// No description provided for @auctionApprovalWaiting.
  ///
  /// In tr, this message translates to:
  /// **'⚡ Onay Bekleniyor'**
  String get auctionApprovalWaiting;

  /// No description provided for @auctionApprovalWaitingDesc.
  ///
  /// In tr, this message translates to:
  /// **'Hemen Al talebiniz host onayına gönderildi.'**
  String get auctionApprovalWaitingDesc;

  /// No description provided for @auctionInProgress.
  ///
  /// In tr, this message translates to:
  /// **'⏳ İşlem Devam Ediyor'**
  String get auctionInProgress;

  /// No description provided for @auctionInProgressDesc.
  ///
  /// In tr, this message translates to:
  /// **'@{username} ile Hemen Al işlemi yapılıyor.'**
  String auctionInProgressDesc(String username);

  /// No description provided for @auctionInProgressNoBid.
  ///
  /// In tr, this message translates to:
  /// **'Sonuçlanana kadar teklif veremezsiniz.'**
  String get auctionInProgressNoBid;

  /// No description provided for @auctionSold.
  ///
  /// In tr, this message translates to:
  /// **'🛒 SATILDI!'**
  String get auctionSold;

  /// No description provided for @auctionBoughtBy.
  ///
  /// In tr, this message translates to:
  /// **'@{username} tarafından Hemen Alındı'**
  String auctionBoughtBy(String username);

  /// No description provided for @auctionBuyNowCongrats.
  ///
  /// In tr, this message translates to:
  /// **'🎉 Tebrikler! Satın alma tamamlandı.'**
  String get auctionBuyNowCongrats;

  /// No description provided for @auctionBuyNowSoldOther.
  ///
  /// In tr, this message translates to:
  /// **'🛒 Ürün Hemen Satıldı! @{buyer} tarafından alındı.'**
  String auctionBuyNowSoldOther(String buyer);

  /// No description provided for @auctionBinRejected.
  ///
  /// In tr, this message translates to:
  /// **'Hemen Al talebiniz reddedildi, artırma devam ediyor.'**
  String get auctionBinRejected;

  /// No description provided for @auctionBinRejectedOther.
  ///
  /// In tr, this message translates to:
  /// **'Hemen Al işlemi sonuçlandı, artırma devam ediyor.'**
  String get auctionBinRejectedOther;

  /// No description provided for @auctionBuyNowBtn.
  ///
  /// In tr, this message translates to:
  /// **'⚡ Hemen Al — '**
  String get auctionBuyNowBtn;

  /// No description provided for @auctionBuyNowBuyBtn.
  ///
  /// In tr, this message translates to:
  /// **'Satın Al'**
  String get auctionBuyNowBuyBtn;

  /// No description provided for @auctionAcceptBtn.
  ///
  /// In tr, this message translates to:
  /// **'✅ Kabul'**
  String get auctionAcceptBtn;

  /// No description provided for @auctionValidAmount.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli tutar girin'**
  String get auctionValidAmount;

  /// No description provided for @auctionCustomAmountHint.
  ///
  /// In tr, this message translates to:
  /// **'Özel tutar (₺)'**
  String get auctionCustomAmountHint;

  /// No description provided for @auctionFirstBid.
  ///
  /// In tr, this message translates to:
  /// **'İlk teklifi sen ver!'**
  String get auctionFirstBid;

  /// No description provided for @auctionHighestBidder.
  ///
  /// In tr, this message translates to:
  /// **'@{username} en yüksek teklif sahibi'**
  String auctionHighestBidder(String username);

  /// No description provided for @auctionBidCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} teklif'**
  String auctionBidCount(int count);

  /// No description provided for @auctionManualEntry.
  ///
  /// In tr, this message translates to:
  /// **'Manuel Gir'**
  String get auctionManualEntry;

  /// No description provided for @auctionFromListings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarımdan'**
  String get auctionFromListings;

  /// No description provided for @auctionNoActiveListings.
  ///
  /// In tr, this message translates to:
  /// **'Aktif ilanınız yok.'**
  String get auctionNoActiveListings;

  /// No description provided for @auctionStartTitle.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırma Başlat'**
  String get auctionStartTitle;

  /// No description provided for @auctionItemName.
  ///
  /// In tr, this message translates to:
  /// **'Ürün adı'**
  String get auctionItemName;

  /// No description provided for @auctionStartPrice.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç fiyatı (₺)'**
  String get auctionStartPrice;

  /// No description provided for @auctionBuyNowPriceHint.
  ///
  /// In tr, this message translates to:
  /// **'Hemen Al fiyatı (₺, opsiyonel)'**
  String get auctionBuyNowPriceHint;

  /// No description provided for @auctionBuyNowCompleted.
  ///
  /// In tr, this message translates to:
  /// **'🛒 Hemen Al tamamlandı! @{buyer} — ₺{price}'**
  String auctionBuyNowCompleted(String buyer, String price);

  /// No description provided for @offerHistory.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Geçmişi'**
  String get offerHistory;

  /// No description provided for @offerAmountHint.
  ///
  /// In tr, this message translates to:
  /// **'Teklif miktarı (₺)'**
  String get offerAmountHint;

  /// No description provided for @offerBtn.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Ver'**
  String get offerBtn;

  /// No description provided for @offerSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Teklifiniz alındı!'**
  String get offerSuccess;

  /// No description provided for @offerError.
  ///
  /// In tr, this message translates to:
  /// **'Teklif gönderilemedi.'**
  String get offerError;

  /// No description provided for @offerInvalidAmount.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir tutar girin.'**
  String get offerInvalidAmount;

  /// No description provided for @offerEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz teklif yok.'**
  String get offerEmpty;

  /// No description provided for @offerLoginRequired.
  ///
  /// In tr, this message translates to:
  /// **'Teklif vermek için giriş yapın.'**
  String get offerLoginRequired;

  /// No description provided for @storyTrayTitle.
  ///
  /// In tr, this message translates to:
  /// **'Takip Ettiklerin'**
  String get storyTrayTitle;

  /// No description provided for @storyTrayEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Şu an takip ettiğin kimse yayında değil.'**
  String get storyTrayEmpty;

  /// No description provided for @storyTrayError.
  ///
  /// In tr, this message translates to:
  /// **'Yüklenemedi'**
  String get storyTrayError;

  /// No description provided for @storyMyStory.
  ///
  /// In tr, this message translates to:
  /// **'Hikayen'**
  String get storyMyStory;

  /// No description provided for @storyProcessing.
  ///
  /// In tr, this message translates to:
  /// **'Video işleniyor...'**
  String get storyProcessing;

  /// No description provided for @storyTooLong.
  ///
  /// In tr, this message translates to:
  /// **'Video çok uzun (en fazla 15 saniye)'**
  String get storyTooLong;

  /// No description provided for @storyUploadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Hikaye yüklenemedi'**
  String get storyUploadFailed;

  /// No description provided for @storyUploadSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Hikayeniz paylaşıldı!'**
  String get storyUploadSuccess;

  /// No description provided for @storyLiveNow.
  ///
  /// In tr, this message translates to:
  /// **'Şu an Canlı Yayında!'**
  String get storyLiveNow;

  /// No description provided for @storyJoinLive.
  ///
  /// In tr, this message translates to:
  /// **'Yayına Katıl'**
  String get storyJoinLive;

  /// No description provided for @storyJoinLiveFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yayına bağlanılamadı'**
  String get storyJoinLiveFailed;

  /// No description provided for @storyWhoViewed.
  ///
  /// In tr, this message translates to:
  /// **'Kim Gördü?'**
  String get storyWhoViewed;

  /// No description provided for @storyViewersLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Görüntüleyenler yüklenemedi'**
  String get storyViewersLoadFailed;

  /// No description provided for @storyNoViewersYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kimse görmedi'**
  String get storyNoViewersYet;

  /// No description provided for @storyDelete.
  ///
  /// In tr, this message translates to:
  /// **'Hikayeyi Sil'**
  String get storyDelete;

  /// No description provided for @storyDeleteConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Bu hikayeyi silmek istediğine emin misin?'**
  String get storyDeleteConfirm;

  /// No description provided for @storyDeleteFailed.
  ///
  /// In tr, this message translates to:
  /// **'Hikaye silinemedi'**
  String get storyDeleteFailed;

  /// No description provided for @offlineBannerMessage.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantısı yok, çevrimdışı moddasınız.'**
  String get offlineBannerMessage;

  /// No description provided for @editProfileBio.
  ///
  /// In tr, this message translates to:
  /// **'Hakkımda'**
  String get editProfileBio;

  /// No description provided for @editProfileBioHint.
  ///
  /// In tr, this message translates to:
  /// **'Kendin hakkında kısa bir şeyler yaz…'**
  String get editProfileBioHint;

  /// No description provided for @editProfileBioHelper.
  ///
  /// In tr, this message translates to:
  /// **'Maks. 60 karakter'**
  String get editProfileBioHelper;

  /// No description provided for @editProfileLink.
  ///
  /// In tr, this message translates to:
  /// **'Link'**
  String get editProfileLink;

  /// No description provided for @editProfileLinkHint.
  ///
  /// In tr, this message translates to:
  /// **'https://...'**
  String get editProfileLinkHint;

  /// No description provided for @editProfileLinkHelper.
  ///
  /// In tr, this message translates to:
  /// **'https:// ile başlamalı'**
  String get editProfileLinkHelper;

  /// No description provided for @editProfileLinkError.
  ///
  /// In tr, this message translates to:
  /// **'Link http:// veya https:// ile başlamalı'**
  String get editProfileLinkError;

  /// No description provided for @settingsProTools.
  ///
  /// In tr, this message translates to:
  /// **'📈 Pro Araçları'**
  String get settingsProTools;

  /// No description provided for @settingsProActive.
  ///
  /// In tr, this message translates to:
  /// **'AKTİF'**
  String get settingsProActive;

  /// No description provided for @walletTitle.
  ///
  /// In tr, this message translates to:
  /// **'TUCi Cüzdanım'**
  String get walletTitle;

  /// No description provided for @walletBalance.
  ///
  /// In tr, this message translates to:
  /// **'Güncel Bakiye'**
  String get walletBalance;

  /// No description provided for @walletRecentTxns.
  ///
  /// In tr, this message translates to:
  /// **'Son İşlemler'**
  String get walletRecentTxns;

  /// No description provided for @walletSpendingSummary.
  ///
  /// In tr, this message translates to:
  /// **'Harcama Özeti'**
  String get walletSpendingSummary;

  /// No description provided for @walletTxnHistory.
  ///
  /// In tr, this message translates to:
  /// **'İşlem Geçmişi'**
  String get walletTxnHistory;

  /// No description provided for @walletNoTxns.
  ///
  /// In tr, this message translates to:
  /// **'Henüz işlem yok.'**
  String get walletNoTxns;

  /// No description provided for @walletTxnAirdrop.
  ///
  /// In tr, this message translates to:
  /// **'Hoş geldin hediyesi'**
  String get walletTxnAirdrop;

  /// No description provided for @walletTxnReceiveGift.
  ///
  /// In tr, this message translates to:
  /// **'Hediye alındı'**
  String get walletTxnReceiveGift;

  /// No description provided for @walletTxnSpendLeadGen.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Duyuru'**
  String get walletTxnSpendLeadGen;

  /// No description provided for @walletTxnSpendAdCampaign.
  ///
  /// In tr, this message translates to:
  /// **'Reklam kampanyası'**
  String get walletTxnSpendAdCampaign;

  /// No description provided for @walletTxnSpendAi.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Zeka fiyatlama'**
  String get walletTxnSpendAi;

  /// No description provided for @walletTxnWebTopup.
  ///
  /// In tr, this message translates to:
  /// **'Web yükleme'**
  String get walletTxnWebTopup;

  /// No description provided for @walletComingSoonLabel.
  ///
  /// In tr, this message translates to:
  /// **'TUCi Satın Alma Yakında!'**
  String get walletComingSoonLabel;

  /// No description provided for @walletComingSoonDesc.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme altyapımız hazırlanıyor. Şu an tüm kullanıcılara 100 TUCi başlangıç bakiyesi tanımlandı.'**
  String get walletComingSoonDesc;

  /// No description provided for @walletBuyBtn.
  ///
  /// In tr, this message translates to:
  /// **'TUCi Satın Alma Yakında'**
  String get walletBuyBtn;

  /// No description provided for @reportLoading.
  ///
  /// In tr, this message translates to:
  /// **'Yayın analizi hazırlanıyor…'**
  String get reportLoading;

  /// No description provided for @reportLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Rapor yüklenemedi.'**
  String get reportLoadFailed;

  /// No description provided for @reportRetry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar Dene'**
  String get reportRetry;

  /// No description provided for @reportGoHome.
  ///
  /// In tr, this message translates to:
  /// **'Ana Sayfaya Dön'**
  String get reportGoHome;

  /// No description provided for @reportBadge.
  ///
  /// In tr, this message translates to:
  /// **'YAYIN ANALİZİ'**
  String get reportBadge;

  /// No description provided for @reportStreamEndedDesc.
  ///
  /// In tr, this message translates to:
  /// **'Yayın sona erdi. Kitle analiziniz aşağıda.'**
  String get reportStreamEndedDesc;

  /// No description provided for @reportMetricPeakViewers.
  ///
  /// In tr, this message translates to:
  /// **'Zirve\nİzleyici'**
  String get reportMetricPeakViewers;

  /// No description provided for @reportMetricEngagedViewers.
  ///
  /// In tr, this message translates to:
  /// **'Etkileşimli\nİzleyici'**
  String get reportMetricEngagedViewers;

  /// No description provided for @reportMetricAvgBudget.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama\nKitle Bütçesi'**
  String get reportMetricAvgBudget;

  /// No description provided for @reportMetricDuration.
  ///
  /// In tr, this message translates to:
  /// **'Yayın\nSüresi'**
  String get reportMetricDuration;

  /// No description provided for @reportSectionSwipeFeed.
  ///
  /// In tr, this message translates to:
  /// **'SWIPE FEED ERİŞİMİ'**
  String get reportSectionSwipeFeed;

  /// No description provided for @reportMetricSwipeImpressions.
  ///
  /// In tr, this message translates to:
  /// **'Swipe Feed\nGörüntülenme'**
  String get reportMetricSwipeImpressions;

  /// No description provided for @reportMetricSwipeReach.
  ///
  /// In tr, this message translates to:
  /// **'Swipe Feed\nTekil Erişim'**
  String get reportMetricSwipeReach;

  /// No description provided for @reportSectionAuction.
  ///
  /// In tr, this message translates to:
  /// **'AÇIK ARTIRMA ÖZETİ'**
  String get reportSectionAuction;

  /// No description provided for @reportMetricTotalAuctions.
  ///
  /// In tr, this message translates to:
  /// **'Toplam\nArtırma'**
  String get reportMetricTotalAuctions;

  /// No description provided for @reportMetricSoldItems.
  ///
  /// In tr, this message translates to:
  /// **'Satılan\nÜrün'**
  String get reportMetricSoldItems;

  /// No description provided for @reportMetricTotalBids.
  ///
  /// In tr, this message translates to:
  /// **'Toplam\nTeklif'**
  String get reportMetricTotalBids;

  /// No description provided for @reportMetricRevenue.
  ///
  /// In tr, this message translates to:
  /// **'Toplam\nHasılat'**
  String get reportMetricRevenue;

  /// No description provided for @reportItemSold.
  ///
  /// In tr, this message translates to:
  /// **'✅ Satıldı'**
  String get reportItemSold;

  /// No description provided for @reportItemBuyNow.
  ///
  /// In tr, this message translates to:
  /// **'⚡ Hemen Al'**
  String get reportItemBuyNow;

  /// No description provided for @reportItemNotSold.
  ///
  /// In tr, this message translates to:
  /// **'❌ Satılmadı'**
  String get reportItemNotSold;

  /// No description provided for @reportChipStart.
  ///
  /// In tr, this message translates to:
  /// **'Başl.'**
  String get reportChipStart;

  /// No description provided for @reportChipSale.
  ///
  /// In tr, this message translates to:
  /// **'Satış'**
  String get reportChipSale;

  /// No description provided for @reportChipBids.
  ///
  /// In tr, this message translates to:
  /// **'Teklif'**
  String get reportChipBids;

  /// No description provided for @reportHesitation.
  ///
  /// In tr, this message translates to:
  /// **'{count} kararsız teklif — bu izleyiciler fiyat noktasına yakın ama dönüştüremedik.'**
  String reportHesitation(int count);

  /// No description provided for @reportSmartInsight.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Öneri'**
  String get reportSmartInsight;

  /// No description provided for @reportDurationMin.
  ///
  /// In tr, this message translates to:
  /// **'dk'**
  String get reportDurationMin;

  /// No description provided for @reportDurationHour.
  ///
  /// In tr, this message translates to:
  /// **'sa'**
  String get reportDurationHour;

  /// No description provided for @reportDurationLess.
  ///
  /// In tr, this message translates to:
  /// **'< 1 dk'**
  String get reportDurationLess;

  /// No description provided for @proLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Veriler yüklenemedi.'**
  String get proLoadFailed;

  /// No description provided for @proUpgradeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Pro Özelliği'**
  String get proUpgradeTitle;

  /// No description provided for @proUpgradeBtn.
  ///
  /// In tr, this message translates to:
  /// **'👑 Pro\'ya Geç'**
  String get proUpgradeBtn;

  /// No description provided for @proHubTitle.
  ///
  /// In tr, this message translates to:
  /// **'Pro Araçları'**
  String get proHubTitle;

  /// No description provided for @proToolSalesTitle.
  ///
  /// In tr, this message translates to:
  /// **'Satış ve Kitle Raporu'**
  String get proToolSalesTitle;

  /// No description provided for @proToolSalesDesc.
  ///
  /// In tr, this message translates to:
  /// **'Gelirler, dönüşüm oranları ve sıcak ilanlarınız'**
  String get proToolSalesDesc;

  /// No description provided for @proToolListingsTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlan Analizleri'**
  String get proToolListingsTitle;

  /// No description provided for @proToolListingsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Hangi ilanınız kaç kişiye ulaştı, kaçı tıkladı'**
  String get proToolListingsDesc;

  /// No description provided for @proToolMarketTitle.
  ///
  /// In tr, this message translates to:
  /// **'Pazar Bilgisi'**
  String get proToolMarketTitle;

  /// No description provided for @proToolMarketDesc.
  ///
  /// In tr, this message translates to:
  /// **'Alıcılar ne arıyor, hangi saatlerde alışveriş yapıyor'**
  String get proToolMarketDesc;

  /// No description provided for @proBlastSection.
  ///
  /// In tr, this message translates to:
  /// **'Kitle Davet Kredisi'**
  String get proBlastSection;

  /// No description provided for @proBenefitsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Pro\'ya Geçince Ne Kazanırsın?'**
  String get proBenefitsTitle;

  /// No description provided for @proBenefit1.
  ///
  /// In tr, this message translates to:
  /// **'Satışlarını ve gelirlerin nereye gittiğini gör'**
  String get proBenefit1;

  /// No description provided for @proBenefit2.
  ///
  /// In tr, this message translates to:
  /// **'Her ilanına kaç kişi baktı, kaçı tıkladı'**
  String get proBenefit2;

  /// No description provided for @proBenefit3.
  ///
  /// In tr, this message translates to:
  /// **'Alıcıların en aktif olduğu saatleri öğren'**
  String get proBenefit3;

  /// No description provided for @proBenefit4.
  ///
  /// In tr, this message translates to:
  /// **'İnsanlar ne arıyor — boşluğu doldur, sat'**
  String get proBenefit4;

  /// No description provided for @proStatusTitle.
  ///
  /// In tr, this message translates to:
  /// **'👑 Pro Kullanıcı'**
  String get proStatusTitle;

  /// No description provided for @proStatusDesc.
  ///
  /// In tr, this message translates to:
  /// **'Tüm analitik araçlara erişiminiz aktif'**
  String get proStatusDesc;

  /// No description provided for @proUnlockTitle.
  ///
  /// In tr, this message translates to:
  /// **'Pro araçları kilidi aç'**
  String get proUnlockTitle;

  /// No description provided for @proUnlockDesc.
  ///
  /// In tr, this message translates to:
  /// **'Verilerle sat, değil tahminle'**
  String get proUnlockDesc;

  /// No description provided for @proUnlockBtn.
  ///
  /// In tr, this message translates to:
  /// **'Pro\'ya Geç'**
  String get proUnlockBtn;

  /// No description provided for @proUpgradeSheetDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu aracı kullanmak için Pro\'ya geçmeniz gerekiyor.'**
  String get proUpgradeSheetDesc;

  /// No description provided for @blastRemainingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu Ay Kalan Hak'**
  String get blastRemainingTitle;

  /// No description provided for @blastCreditEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Bu ay duyuru krediniz doldu. Yeni ayda yenilenir.'**
  String get blastCreditEmpty;

  /// No description provided for @blastCreditUsed.
  ///
  /// In tr, this message translates to:
  /// **'{used} duyuru gönderdiniz, {remaining} hakkınız kaldı.'**
  String blastCreditUsed(int used, int remaining);

  /// No description provided for @proAnalyticsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Pro Analitik'**
  String get proAnalyticsTitle;

  /// No description provided for @proSectionOverview.
  ///
  /// In tr, this message translates to:
  /// **'Satış Özetim'**
  String get proSectionOverview;

  /// No description provided for @proSectionFunnel.
  ///
  /// In tr, this message translates to:
  /// **'Kaç Kişi Teklif Verdi?'**
  String get proSectionFunnel;

  /// No description provided for @proSectionTips.
  ///
  /// In tr, this message translates to:
  /// **'🤖 Akıllı Öneriler'**
  String get proSectionTips;

  /// No description provided for @proSectionHotLeads.
  ///
  /// In tr, this message translates to:
  /// **'Fırsatı Kaçırma'**
  String get proSectionHotLeads;

  /// No description provided for @proHotLeadsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu alıcılar ilanına baktı ama teklif vermedi — fiyatı düşür veya öne çıkar'**
  String get proHotLeadsDesc;

  /// No description provided for @proSectionPriceIntel.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatın Piyasada Nerede?'**
  String get proSectionPriceIntel;

  /// No description provided for @proPriceIntelDesc.
  ///
  /// In tr, this message translates to:
  /// **'Benzer ilanlarla karşılaştırarak doğru fiyatı bul'**
  String get proPriceIntelDesc;

  /// No description provided for @proSectionStreamPerf.
  ///
  /// In tr, this message translates to:
  /// **'Yayınlarım Nasıl Gidiyor?'**
  String get proSectionStreamPerf;

  /// No description provided for @proSectionPeakHours.
  ///
  /// In tr, this message translates to:
  /// **'Platform En Çok Kaçta Aktif?'**
  String get proSectionPeakHours;

  /// No description provided for @proPeakHoursDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu saatlerde yayın yap, daha fazla izleyiciye ulaş'**
  String get proPeakHoursDesc;

  /// No description provided for @proKpiRevenue30d.
  ///
  /// In tr, this message translates to:
  /// **'Son 30 Gün Gelir'**
  String get proKpiRevenue30d;

  /// No description provided for @proKpiLast30d.
  ///
  /// In tr, this message translates to:
  /// **'son 30 gün'**
  String get proKpiLast30d;

  /// No description provided for @proKpiSales.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Satış'**
  String get proKpiSales;

  /// No description provided for @proKpiBids.
  ///
  /// In tr, this message translates to:
  /// **'Gelen Teklifler'**
  String get proKpiBids;

  /// No description provided for @proKpiActiveListings.
  ///
  /// In tr, this message translates to:
  /// **'Aktif İlanlar'**
  String get proKpiActiveListings;

  /// No description provided for @proKpiItemUnit.
  ///
  /// In tr, this message translates to:
  /// **'adet'**
  String get proKpiItemUnit;

  /// No description provided for @proKpiBidUnit.
  ///
  /// In tr, this message translates to:
  /// **'teklif'**
  String get proKpiBidUnit;

  /// No description provided for @proKpiListingUnit.
  ///
  /// In tr, this message translates to:
  /// **'ilan'**
  String get proKpiListingUnit;

  /// No description provided for @proKpiTotalUnit.
  ///
  /// In tr, this message translates to:
  /// **'toplam'**
  String get proKpiTotalUnit;

  /// No description provided for @proFunnelViews.
  ///
  /// In tr, this message translates to:
  /// **'Kaç kişi gördü'**
  String get proFunnelViews;

  /// No description provided for @proFunnelHesitation.
  ///
  /// In tr, this message translates to:
  /// **'Kaç kişi tereddüt etti'**
  String get proFunnelHesitation;

  /// No description provided for @proFunnelBid.
  ///
  /// In tr, this message translates to:
  /// **'Kaç kişi teklif verdi'**
  String get proFunnelBid;

  /// No description provided for @proFunnelSale.
  ///
  /// In tr, this message translates to:
  /// **'Kaç satış yapıldı'**
  String get proFunnelSale;

  /// No description provided for @proFunnelViewToBid.
  ///
  /// In tr, this message translates to:
  /// **'Görenlerin kaçı teklif verdi'**
  String get proFunnelViewToBid;

  /// No description provided for @proFunnelBidToSale.
  ///
  /// In tr, this message translates to:
  /// **'Tekliflerin kaçı satışa döndü'**
  String get proFunnelBidToSale;

  /// No description provided for @priceSignalExpensive.
  ///
  /// In tr, this message translates to:
  /// **'⬆ Pahalı'**
  String get priceSignalExpensive;

  /// No description provided for @priceSignalCheap.
  ///
  /// In tr, this message translates to:
  /// **'⬇ Ucuz'**
  String get priceSignalCheap;

  /// No description provided for @priceSignalFair.
  ///
  /// In tr, this message translates to:
  /// **'✓ Uygun'**
  String get priceSignalFair;

  /// No description provided for @priceYours.
  ///
  /// In tr, this message translates to:
  /// **'Senin Fiyatın'**
  String get priceYours;

  /// No description provided for @priceMarketAvg.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa Ortalaması'**
  String get priceMarketAvg;

  /// No description provided for @priceDiff.
  ///
  /// In tr, this message translates to:
  /// **'Fark'**
  String get priceDiff;

  /// No description provided for @proNoStreams.
  ///
  /// In tr, this message translates to:
  /// **'Henüz canlı yayın yapılmadı.'**
  String get proNoStreams;

  /// No description provided for @proStreamTotal.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Yayın'**
  String get proStreamTotal;

  /// No description provided for @proStreamThisMonth.
  ///
  /// In tr, this message translates to:
  /// **'Bu Ay'**
  String get proStreamThisMonth;

  /// No description provided for @proStreamAvgViewers.
  ///
  /// In tr, this message translates to:
  /// **'Ort. İzleyen'**
  String get proStreamAvgViewers;

  /// No description provided for @proStreamPeak.
  ///
  /// In tr, this message translates to:
  /// **'En Yüksek'**
  String get proStreamPeak;

  /// No description provided for @proStreamAvgDuration.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama yayın süresi: {dur} dakika'**
  String proStreamAvgDuration(String dur);

  /// No description provided for @proEngagements.
  ///
  /// In tr, this message translates to:
  /// **'etk.'**
  String get proEngagements;

  /// No description provided for @proShowAll.
  ///
  /// In tr, this message translates to:
  /// **'{count} tanesini daha gör'**
  String proShowAll(int count);

  /// No description provided for @proShowLess.
  ///
  /// In tr, this message translates to:
  /// **'Daha az göster'**
  String get proShowLess;

  /// No description provided for @proStreamRowStats.
  ///
  /// In tr, this message translates to:
  /// **'{viewers} izleyici · {bids} teklif · {dur} dk'**
  String proStreamRowStats(int viewers, int bids, int dur);

  /// No description provided for @proLoadError.
  ///
  /// In tr, this message translates to:
  /// **'Veriler yüklenemedi. Lütfen tekrar deneyin.'**
  String get proLoadError;

  /// No description provided for @hotLeadViewed.
  ///
  /// In tr, this message translates to:
  /// **'{count} kez bakıldı'**
  String hotLeadViewed(int count);

  /// No description provided for @hotLeadHesitated.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişi tereddüt etti'**
  String hotLeadHesitated(int count);

  /// No description provided for @listingCtrExplain.
  ///
  /// In tr, this message translates to:
  /// **'Her 100 görüntülemede {ctr} tıklama'**
  String listingCtrExplain(String ctr);

  /// No description provided for @marketSearchTitle.
  ///
  /// In tr, this message translates to:
  /// **'İnsanlar şunları arıyor'**
  String get marketSearchTitle;

  /// No description provided for @marketDayFilter.
  ///
  /// In tr, this message translates to:
  /// **'{days} gün'**
  String marketDayFilter(int days);

  /// No description provided for @marketNoSearchData.
  ///
  /// In tr, this message translates to:
  /// **'Henüz arama verisi yok. Kullanıcılar arama yaptıkça burada görünecek.'**
  String get marketNoSearchData;

  /// No description provided for @marketCategoryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hangi kategoride arıyorlar'**
  String get marketCategoryTitle;

  /// No description provided for @marketPeakHoursTitle.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş en çok bu saatlerde'**
  String get marketPeakHoursTitle;

  /// No description provided for @marketPeakHoursDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarınızı bu saatlerde yayınlarsanız daha fazla kişiye ulaşırsınız.'**
  String get marketPeakHoursDesc;

  /// No description provided for @marketNoActivityData.
  ///
  /// In tr, this message translates to:
  /// **'Henüz yeterli aktivite verisi yok.'**
  String get marketNoActivityData;

  /// No description provided for @marketTrendingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu kategoriler ilgi görüyor'**
  String get marketTrendingTitle;

  /// No description provided for @marketTrendingDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu kategorilerde ilan açmak satış şansınızı artırabilir.'**
  String get marketTrendingDesc;

  /// No description provided for @marketGrowthPos.
  ///
  /// In tr, this message translates to:
  /// **'Platform genel büyüme: +{pct}%'**
  String marketGrowthPos(String pct);

  /// No description provided for @marketGrowthNeg.
  ///
  /// In tr, this message translates to:
  /// **'Platform genel düşüş: {pct}%'**
  String marketGrowthNeg(String pct);

  /// No description provided for @marketGrowthSub.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama alışveriş tutarı — önceki 30 güne kıyasla'**
  String get marketGrowthSub;

  /// No description provided for @marketPaywallDesc.
  ///
  /// In tr, this message translates to:
  /// **'Alıcılar ne arıyor, hangi saatlerde alışveriş yapıyor, hangi kategoriler yükseliyor — hepsini görün.'**
  String get marketPaywallDesc;

  /// No description provided for @listingPerfTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarınızın Performansı'**
  String get listingPerfTitle;

  /// No description provided for @listingNoDataTitle.
  ///
  /// In tr, this message translates to:
  /// **'Henüz veri yok'**
  String get listingNoDataTitle;

  /// No description provided for @listingNoDataDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarınız swipe feed\'de gösterime girince buradaki veriler dolmaya başlayacak.'**
  String get listingNoDataDesc;

  /// No description provided for @listingDayFilterN.
  ///
  /// In tr, this message translates to:
  /// **'Son {n} Gün'**
  String listingDayFilterN(int n);

  /// No description provided for @listingTotalViews.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Görüntülenme'**
  String get listingTotalViews;

  /// No description provided for @listingAvgCtr.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama Tıklanma'**
  String get listingAvgCtr;

  /// No description provided for @listingVideoBeatsPhoto.
  ///
  /// In tr, this message translates to:
  /// **'🎬 Videolu ilanlarınız, fotoğraflılara göre {x} kat daha fazla tıklanıyor.'**
  String listingVideoBeatsPhoto(String x);

  /// No description provided for @listingPhotoBeatsVideo.
  ///
  /// In tr, this message translates to:
  /// **'📸 Fotoğraflı ilanlarınız, videolulara göre {x} kat daha fazla tıklanıyor.'**
  String listingPhotoBeatsVideo(String x);

  /// No description provided for @listingMediaEqual.
  ///
  /// In tr, this message translates to:
  /// **'Video ve fotoğraflı ilanlarınız benzer ilgi görüyor.'**
  String get listingMediaEqual;

  /// No description provided for @listingVideoLabel.
  ///
  /// In tr, this message translates to:
  /// **'Videolu'**
  String get listingVideoLabel;

  /// No description provided for @listingPhotoLabel.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraflı'**
  String get listingPhotoLabel;

  /// No description provided for @listingWatchRateLabel.
  ///
  /// In tr, this message translates to:
  /// **'İzleme oranı'**
  String get listingWatchRateLabel;

  /// No description provided for @listingWatchedPct.
  ///
  /// In tr, this message translates to:
  /// **'%{pct} izlendi'**
  String listingWatchedPct(String pct);

  /// No description provided for @listingGalleryLabel.
  ///
  /// In tr, this message translates to:
  /// **'Galeri ilgisi'**
  String get listingGalleryLabel;

  /// No description provided for @listingGalleryDeep.
  ///
  /// In tr, this message translates to:
  /// **'{n}. fotoğrafa kadar baktı'**
  String listingGalleryDeep(String n);

  /// No description provided for @listingGalleryShallow.
  ///
  /// In tr, this message translates to:
  /// **'Sadece ilk fotoğrafa baktı'**
  String get listingGalleryShallow;

  /// No description provided for @metricViewed.
  ///
  /// In tr, this message translates to:
  /// **'gördü'**
  String get metricViewed;

  /// No description provided for @metricClicked.
  ///
  /// In tr, this message translates to:
  /// **'tıkladı'**
  String get metricClicked;

  /// No description provided for @listingPaywallDesc.
  ///
  /// In tr, this message translates to:
  /// **'Her ilanınızın kaç kişiye ulaştığını, kaçının tıkladığını ve ne kadar ilgi gördüğünü takip edin.'**
  String get listingPaywallDesc;

  /// No description provided for @onboardingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Nelerle ilgileniyorsun?'**
  String get onboardingTitle;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Sana özel ilan ve yayınlar gösterelim'**
  String get onboardingSubtitle;

  /// No description provided for @onboardingMinHint.
  ///
  /// In tr, this message translates to:
  /// **'En az 3 kategori seç'**
  String get onboardingMinHint;

  /// No description provided for @onboardingContinue.
  ///
  /// In tr, this message translates to:
  /// **'Devam Et'**
  String get onboardingContinue;

  /// No description provided for @onboardingSkip.
  ///
  /// In tr, this message translates to:
  /// **'Şimdilik Atla'**
  String get onboardingSkip;

  /// No description provided for @onboardingBannerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sana özel ilanlar gösterelim'**
  String get onboardingBannerTitle;

  /// No description provided for @onboardingBannerSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'İlgi alanlarını seç, feed\'in kişiselleşsin.'**
  String get onboardingBannerSubtitle;

  /// No description provided for @onboardingBannerCta.
  ///
  /// In tr, this message translates to:
  /// **'Seç'**
  String get onboardingBannerCta;

  /// No description provided for @updateRequiredTitle.
  ///
  /// In tr, this message translates to:
  /// **'Güncelleme Gerekli'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredDesc.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamanın en iyi şekilde çalışması için lütfen güncel sürüme geçin.'**
  String get updateRequiredDesc;

  /// No description provided for @updateRequiredBtn.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi Güncelle'**
  String get updateRequiredBtn;

  /// No description provided for @chatRateLimited.
  ///
  /// In tr, this message translates to:
  /// **'Biraz yavaşla 🐢'**
  String get chatRateLimited;

  /// No description provided for @fraudInvalidBid.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz İşlem'**
  String get fraudInvalidBid;

  /// No description provided for @fraudShieldTitle.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik Doğrulaması Gerekli'**
  String get fraudShieldTitle;

  /// No description provided for @fraudShieldDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu kadar yüksek bir teklif verebilmek için hesabının gerçek bir kişiye ait olduğunu doğrulamamız gerekiyor. Bu sadece 1 dakikanı alır.'**
  String get fraudShieldDesc;

  /// No description provided for @fraudShieldVerifyBtn.
  ///
  /// In tr, this message translates to:
  /// **'Telefonumu Doğrula'**
  String get fraudShieldVerifyBtn;

  /// No description provided for @fraudShieldDismiss.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi değil'**
  String get fraudShieldDismiss;

  /// No description provided for @tabListings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlar'**
  String get tabListings;

  /// No description provided for @tabPurchases.
  ///
  /// In tr, this message translates to:
  /// **'Alışverişler'**
  String get tabPurchases;

  /// No description provided for @purchasesEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz satın alma yok'**
  String get purchasesEmpty;

  /// No description provided for @purchasesEmptyHint.
  ///
  /// In tr, this message translates to:
  /// **'Canlı yayınlarda açık artırmaya katıl'**
  String get purchasesEmptyHint;

  /// No description provided for @badgeTrustedSeller.
  ///
  /// In tr, this message translates to:
  /// **'✅ Güvenilir'**
  String get badgeTrustedSeller;

  /// No description provided for @badgeActiveSeller.
  ///
  /// In tr, this message translates to:
  /// **'⭐ Aktif'**
  String get badgeActiveSeller;

  /// No description provided for @badgeTrending.
  ///
  /// In tr, this message translates to:
  /// **'🔥 Trend'**
  String get badgeTrending;

  /// No description provided for @searchAlertTitle.
  ///
  /// In tr, this message translates to:
  /// **'Arama Alarmı'**
  String get searchAlertTitle;

  /// No description provided for @searchAlertBody.
  ///
  /// In tr, this message translates to:
  /// **'\"{query}\" için yeni ilan eklendiğinde bildirim al.'**
  String searchAlertBody(String query);

  /// No description provided for @searchAlertCreate.
  ///
  /// In tr, this message translates to:
  /// **'Alarm Oluştur'**
  String get searchAlertCreate;

  /// No description provided for @searchAlertCreated.
  ///
  /// In tr, this message translates to:
  /// **'Arama alarmı oluşturuldu ✓'**
  String get searchAlertCreated;

  /// No description provided for @searchAlertFailed.
  ///
  /// In tr, this message translates to:
  /// **'Alarm oluşturulamadı, tekrar dene'**
  String get searchAlertFailed;

  /// No description provided for @searchAlertTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Arama Alarmı Oluştur'**
  String get searchAlertTooltip;

  /// No description provided for @audienceInsightsTitle.
  ///
  /// In tr, this message translates to:
  /// **'İzleyici Bütçe Analizi'**
  String get audienceInsightsTitle;

  /// No description provided for @audienceInsightsViewers.
  ///
  /// In tr, this message translates to:
  /// **'{count} izleyici'**
  String audienceInsightsViewers(int count);

  /// No description provided for @audienceAvgBudget.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama Bütçe'**
  String get audienceAvgBudget;

  /// No description provided for @audienceProViewers.
  ///
  /// In tr, this message translates to:
  /// **'Pro İzleyici'**
  String get audienceProViewers;

  /// No description provided for @audienceHighBudget.
  ///
  /// In tr, this message translates to:
  /// **'Yüksek Bütçe (1000₺+)'**
  String get audienceHighBudget;

  /// No description provided for @audienceMedBudget.
  ///
  /// In tr, this message translates to:
  /// **'Orta Bütçe (250-999₺)'**
  String get audienceMedBudget;

  /// No description provided for @audienceLowBudget.
  ///
  /// In tr, this message translates to:
  /// **'Düşük Bütçe (<250₺)'**
  String get audienceLowBudget;

  /// No description provided for @proToolBestTimeTitle.
  ///
  /// In tr, this message translates to:
  /// **'En İyi Yayın Saati'**
  String get proToolBestTimeTitle;

  /// No description provided for @proToolBestTimeDesc.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş yayın verilerinize göre en yüksek dönüşüm sağlayan gün ve saat dilimlerini görün.'**
  String get proToolBestTimeDesc;

  /// No description provided for @proToolConversionTitle.
  ///
  /// In tr, this message translates to:
  /// **'Dönüşüm Analizi'**
  String get proToolConversionTitle;

  /// No description provided for @proToolConversionDesc.
  ///
  /// In tr, this message translates to:
  /// **'Kategori bazlı açık artırma kazanma oranlarınızı ve ortalama satış fiyatlarını inceleyin.'**
  String get proToolConversionDesc;

  /// No description provided for @bestTimeNoData.
  ///
  /// In tr, this message translates to:
  /// **'Henüz yeterli yayın verisi yok'**
  String get bestTimeNoData;

  /// No description provided for @bestTimeNoDataHint.
  ///
  /// In tr, this message translates to:
  /// **'En az 1 yayın yapıldıktan sonra analiz hazır olacak'**
  String get bestTimeNoDataHint;

  /// No description provided for @bestTimeSlotsHeader.
  ///
  /// In tr, this message translates to:
  /// **'En İyi Zaman Dilimleri'**
  String get bestTimeSlotsHeader;

  /// No description provided for @bestTimeSlotStats.
  ///
  /// In tr, this message translates to:
  /// **'{wins} satış / {count} yayın'**
  String bestTimeSlotStats(int wins, int count);

  /// No description provided for @conversionNoData.
  ///
  /// In tr, this message translates to:
  /// **'Henüz satış verisi yok'**
  String get conversionNoData;

  /// No description provided for @conversionNoDataHint.
  ///
  /// In tr, this message translates to:
  /// **'Canlı yayında açık artırma düzenledikten sonra burada satışlarını göreceksin'**
  String get conversionNoDataHint;

  /// No description provided for @conversionSectionHeader.
  ///
  /// In tr, this message translates to:
  /// **'Hangi Kategoride Daha Çok Satıyorsun? (Son 90 Gün)'**
  String get conversionSectionHeader;

  /// No description provided for @conversionCategoryCount.
  ///
  /// In tr, this message translates to:
  /// **'Toplam {count} kategori'**
  String conversionCategoryCount(int count);

  /// No description provided for @conversionCategorySales.
  ///
  /// In tr, this message translates to:
  /// **'{won}/{total} satış'**
  String conversionCategorySales(int won, int total);

  /// No description provided for @conversionAvgPrice.
  ///
  /// In tr, this message translates to:
  /// **'Ort. {price} ₺'**
  String conversionAvgPrice(String price);

  /// No description provided for @accountInfoTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bilgilerim'**
  String get accountInfoTitle;

  /// No description provided for @accountInfoBasicSection.
  ///
  /// In tr, this message translates to:
  /// **'Temel Bilgiler'**
  String get accountInfoBasicSection;

  /// No description provided for @accountInfoSecuritySection.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Güvenliği'**
  String get accountInfoSecuritySection;

  /// No description provided for @accountInfoFullName.
  ///
  /// In tr, this message translates to:
  /// **'Ad Soyad'**
  String get accountInfoFullName;

  /// No description provided for @accountInfoUsername.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı Adı'**
  String get accountInfoUsername;

  /// No description provided for @accountInfoBio.
  ///
  /// In tr, this message translates to:
  /// **'Biyografi'**
  String get accountInfoBio;

  /// No description provided for @accountInfoWebsite.
  ///
  /// In tr, this message translates to:
  /// **'Web Sitesi'**
  String get accountInfoWebsite;

  /// No description provided for @accountInfoEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get accountInfoEmail;

  /// No description provided for @accountInfoPhone.
  ///
  /// In tr, this message translates to:
  /// **'Telefon'**
  String get accountInfoPhone;

  /// No description provided for @accountInfoPhoneEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Eklenmemiş'**
  String get accountInfoPhoneEmpty;

  /// No description provided for @accountInfoVerified.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulandı'**
  String get accountInfoVerified;

  /// No description provided for @accountInfoUnverified.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulanmamış'**
  String get accountInfoUnverified;

  /// No description provided for @accountInfoSave.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get accountInfoSave;

  /// No description provided for @accountInfoUsernameTaken.
  ///
  /// In tr, this message translates to:
  /// **'Bu kullanıcı adı alınmış'**
  String get accountInfoUsernameTaken;

  /// No description provided for @accountInfoSaved.
  ///
  /// In tr, this message translates to:
  /// **'Bilgiler güncellendi'**
  String get accountInfoSaved;

  /// No description provided for @accountInfoEmailChangeTitle.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Değiştir'**
  String get accountInfoEmailChangeTitle;

  /// No description provided for @accountInfoEmailCurrent.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut: {email}'**
  String accountInfoEmailCurrent(String email);

  /// No description provided for @accountInfoNewEmail.
  ///
  /// In tr, this message translates to:
  /// **'Yeni e-posta adresi'**
  String get accountInfoNewEmail;

  /// No description provided for @accountInfoVerifyCode.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu'**
  String get accountInfoVerifyCode;

  /// No description provided for @accountInfoSendCode.
  ///
  /// In tr, this message translates to:
  /// **'Kod Gönder'**
  String get accountInfoSendCode;

  /// No description provided for @accountInfoVerifyCodeBtn.
  ///
  /// In tr, this message translates to:
  /// **'Kodu Doğrula'**
  String get accountInfoVerifyCodeBtn;

  /// No description provided for @accountInfoCodeSent.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu gönderildi'**
  String get accountInfoCodeSent;

  /// No description provided for @accountInfoEmailUpdated.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresiniz güncellendi'**
  String get accountInfoEmailUpdated;

  /// No description provided for @accountInfoDifferentEmail.
  ///
  /// In tr, this message translates to:
  /// **'Farklı e-posta gir'**
  String get accountInfoDifferentEmail;

  /// No description provided for @accountInfoPhoneAddTitle.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Ekle'**
  String get accountInfoPhoneAddTitle;

  /// No description provided for @accountInfoPhoneChangeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Telefonu Değiştir'**
  String get accountInfoPhoneChangeTitle;

  /// No description provided for @accountInfoPhoneCurrent.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut: {phone}'**
  String accountInfoPhoneCurrent(String phone);

  /// No description provided for @accountInfoPhoneSendVerify.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama E-postası Gönder'**
  String get accountInfoPhoneSendVerify;

  /// No description provided for @accountInfoEmailSent.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Gönderildi'**
  String get accountInfoEmailSent;

  /// No description provided for @accountInfoEmailSentDesc.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı e-posta adresinize doğrulama bağlantısı gönderdik. Bağlantıya tıklayarak telefon numaranızı doğrulayın.'**
  String get accountInfoEmailSentDesc;

  /// No description provided for @accountInfoCancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get accountInfoCancel;

  /// No description provided for @accountInfoOk.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get accountInfoOk;

  /// No description provided for @accountInfoConnectError.
  ///
  /// In tr, this message translates to:
  /// **'Sunucuya bağlanılamadı'**
  String get accountInfoConnectError;

  /// No description provided for @accountInfoMenuLabel.
  ///
  /// In tr, this message translates to:
  /// **'Bilgilerim'**
  String get accountInfoMenuLabel;

  /// No description provided for @phoneInfoTitle.
  ///
  /// In tr, this message translates to:
  /// **'Neden telefon numarası?'**
  String get phoneInfoTitle;

  /// No description provided for @phoneInfoBody.
  ///
  /// In tr, this message translates to:
  /// **'Telefon numaranız, yüksek tutarlı tekliflerde hesabınızın güvenliğini sağlamak için kullanılır. Sahte teklifleri önlemek ve kazandığınızda size ulaşabilmek için bu bilgiyi doğrulamamız gerekir. Numaranız hiçbir zaman üçüncü taraflarla paylaşılmaz.'**
  String get phoneInfoBody;

  /// No description provided for @phoneInfoGotIt.
  ///
  /// In tr, this message translates to:
  /// **'Anladım'**
  String get phoneInfoGotIt;

  /// No description provided for @boostOnlyPro.
  ///
  /// In tr, this message translates to:
  /// **'⭐ İlan öne çıkarma yalnızca Pro üyelere özeldir.'**
  String get boostOnlyPro;

  /// No description provided for @boostLimitExhausted.
  ///
  /// In tr, this message translates to:
  /// **'Bu ay {limit} boost hakkını kullandın. Yeni ay başında sıfırlanır.'**
  String boostLimitExhausted(int limit);

  /// No description provided for @boostDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Öne Çıkar'**
  String get boostDialogTitle;

  /// No description provided for @boostDialogPlanLabel.
  ///
  /// In tr, this message translates to:
  /// **'Kampanya planı:'**
  String get boostDialogPlanLabel;

  /// No description provided for @boostDialogTotalBudget.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Bütçe'**
  String get boostDialogTotalBudget;

  /// No description provided for @boostDialogTotalBudgetValue.
  ///
  /// In tr, this message translates to:
  /// **'50 TUCi'**
  String get boostDialogTotalBudgetValue;

  /// No description provided for @boostDialogCpc.
  ///
  /// In tr, this message translates to:
  /// **'Tıklama Başı Maliyet'**
  String get boostDialogCpc;

  /// No description provided for @boostDialogCpcValue.
  ///
  /// In tr, this message translates to:
  /// **'1 TUCi'**
  String get boostDialogCpcValue;

  /// No description provided for @boostDialogEstClicks.
  ///
  /// In tr, this message translates to:
  /// **'Tahmini Tıklama'**
  String get boostDialogEstClicks;

  /// No description provided for @boostDialogEstClicksValue.
  ///
  /// In tr, this message translates to:
  /// **'~50 tıklama'**
  String get boostDialogEstClicksValue;

  /// No description provided for @boostDialogFeedHint.
  ///
  /// In tr, this message translates to:
  /// **'İlanınız \"Sana Özel\" akışında öne çıkarılacak.'**
  String get boostDialogFeedHint;

  /// No description provided for @boostDialogCredits.
  ///
  /// In tr, this message translates to:
  /// **'⭐ Kalan boost hakkı: {remaining} / {limit}'**
  String boostDialogCredits(int remaining, int limit);

  /// No description provided for @boostDialogStart.
  ///
  /// In tr, this message translates to:
  /// **'Başlat'**
  String get boostDialogStart;

  /// No description provided for @boostSuccess.
  ///
  /// In tr, this message translates to:
  /// **'🔥 İlanınız öne çıkarıldı!'**
  String get boostSuccess;

  /// No description provided for @boostErrorDefault.
  ///
  /// In tr, this message translates to:
  /// **'Kampanya başlatılamadı.'**
  String get boostErrorDefault;

  /// No description provided for @boostErrorConnection.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı hatası. Lütfen tekrar deneyin.'**
  String get boostErrorConnection;

  /// No description provided for @boostBtnStart.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Öne Çıkar'**
  String get boostBtnStart;

  /// No description provided for @boostBtnReport.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Performansını Gör'**
  String get boostBtnReport;

  /// No description provided for @adReportTitle.
  ///
  /// In tr, this message translates to:
  /// **'REKLAM RAPORU'**
  String get adReportTitle;

  /// No description provided for @adReportSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kampanyanızın gerçek zamanlı performansı'**
  String get adReportSubtitle;

  /// No description provided for @adReportLoading.
  ///
  /// In tr, this message translates to:
  /// **'Reklam analizi hazırlanıyor…'**
  String get adReportLoading;

  /// No description provided for @adReportLoadError.
  ///
  /// In tr, this message translates to:
  /// **'Rapor yüklenemedi.'**
  String get adReportLoadError;

  /// No description provided for @adReportStatusActive.
  ///
  /// In tr, this message translates to:
  /// **'Aktif'**
  String get adReportStatusActive;

  /// No description provided for @adReportStatusCompleted.
  ///
  /// In tr, this message translates to:
  /// **'Tamamlandı'**
  String get adReportStatusCompleted;

  /// No description provided for @adReportStatusPaused.
  ///
  /// In tr, this message translates to:
  /// **'Duraklatıldı'**
  String get adReportStatusPaused;

  /// No description provided for @adReportStatusCancelled.
  ///
  /// In tr, this message translates to:
  /// **'İptal Edildi'**
  String get adReportStatusCancelled;

  /// No description provided for @adReportMetricImpressions.
  ///
  /// In tr, this message translates to:
  /// **'Gösterim'**
  String get adReportMetricImpressions;

  /// No description provided for @adReportMetricClicks.
  ///
  /// In tr, this message translates to:
  /// **'Tıklama'**
  String get adReportMetricClicks;

  /// No description provided for @adReportMetricClickRate.
  ///
  /// In tr, this message translates to:
  /// **'Her 100 Görüntülemede\nKaç Kişi Tıkladı'**
  String get adReportMetricClickRate;

  /// No description provided for @adReportMetricClickRateHint.
  ///
  /// In tr, this message translates to:
  /// **'{clicks} tıklama / {impressions} görüntüleme'**
  String adReportMetricClickRateHint(int clicks, int impressions);

  /// No description provided for @adReportMetricActiveDays.
  ///
  /// In tr, this message translates to:
  /// **'Aktif\nSüre'**
  String get adReportMetricActiveDays;

  /// No description provided for @adReportMetricActiveDaysLessThan1.
  ///
  /// In tr, this message translates to:
  /// **'<1 gün'**
  String get adReportMetricActiveDaysLessThan1;

  /// No description provided for @adReportMetricActiveDaysValue.
  ///
  /// In tr, this message translates to:
  /// **'{days} gün'**
  String adReportMetricActiveDaysValue(int days);

  /// No description provided for @adReportSmartAnalysis.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Analiz'**
  String get adReportSmartAnalysis;

  /// No description provided for @adReportInsightNoImpressions.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kimse ilanınızı görmedi. İlan akışa girdiğinde burası güncellenecek.'**
  String get adReportInsightNoImpressions;

  /// No description provided for @adReportInsightGreat.
  ///
  /// In tr, this message translates to:
  /// **'Harika! İlanınızı gören her 100 kişiden {clicks}\'i tıkladı — bu çok iyi bir ilgi oranı. İlan başlığı ve görseli alıcıları çekiyor.'**
  String adReportInsightGreat(int clicks);

  /// No description provided for @adReportInsightGood.
  ///
  /// In tr, this message translates to:
  /// **'İyi gidiyorsunuz. {impressions} kişi ilanınızı gördü, {clicks}\'i inceledi. Fotoğrafları veya başlığı geliştirerek daha fazla ilgi çekebilirsiniz.'**
  String adReportInsightGood(int clicks, int impressions);

  /// No description provided for @adReportInsightLow.
  ///
  /// In tr, this message translates to:
  /// **'{impressions} kişi ilanınızı gördü ama sadece {clicks}\'i tıkladı. İlan kapak fotoğrafı veya fiyat, alıcıları yeterince çekmemiş olabilir.'**
  String adReportInsightLow(int clicks, int impressions);

  /// No description provided for @adReportInsightVeryLow.
  ///
  /// In tr, this message translates to:
  /// **'{impressions} kişi ilanınızı gördü, {clicks} tıklama aldı. İlan başlığını, fotoğrafını ve fiyatını gözden geçirmenizi öneririz.'**
  String adReportInsightVeryLow(int clicks, int impressions);

  /// No description provided for @notInterested.
  ///
  /// In tr, this message translates to:
  /// **'İlgilenmiyorum'**
  String get notInterested;

  /// No description provided for @notInterestedConfirmed.
  ///
  /// In tr, this message translates to:
  /// **'Bu ilan bir daha gösterilmeyecek.'**
  String get notInterestedConfirmed;

  /// No description provided for @proMetricAvgDwell.
  ///
  /// In tr, this message translates to:
  /// **'Ort. İnceleme Süresi'**
  String get proMetricAvgDwell;

  /// No description provided for @proMetricSearchVisibility.
  ///
  /// In tr, this message translates to:
  /// **'Arama Görünürlüğü'**
  String get proMetricSearchVisibility;

  /// No description provided for @proMetricBestHour.
  ///
  /// In tr, this message translates to:
  /// **'En İyi Paylaşım Saati'**
  String get proMetricBestHour;

  /// No description provided for @proMetricReturnViewers.
  ///
  /// In tr, this message translates to:
  /// **'Geri Dönen İzleyiciler'**
  String get proMetricReturnViewers;

  /// No description provided for @adMetricDailyTrend.
  ///
  /// In tr, this message translates to:
  /// **'Günlük CTR Trendi'**
  String get adMetricDailyTrend;

  /// No description provided for @adMetricBestHour.
  ///
  /// In tr, this message translates to:
  /// **'En İyi Saat'**
  String get adMetricBestHour;

  /// No description provided for @adMetricCategoryAvgCtr.
  ///
  /// In tr, this message translates to:
  /// **'Kategori Ort. CTR'**
  String get adMetricCategoryAvgCtr;

  /// No description provided for @adMetricBurnRate.
  ///
  /// In tr, this message translates to:
  /// **'Bütçe Tükenme Hızı'**
  String get adMetricBurnRate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
