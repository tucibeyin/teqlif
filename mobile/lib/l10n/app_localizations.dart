import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

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

  /// No description provided for @fieldPasswordConfirmHint.
  ///
  /// In tr, this message translates to:
  /// **'Onaylamak için şifrenizi girin'**
  String get fieldPasswordConfirmHint;

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
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
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
