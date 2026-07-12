import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
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
    Locale('ru'),
    Locale('tr'),
  ];

  /// No description provided for @appName.
  ///
  /// In tr, this message translates to:
  /// **'teqlif'**
  String get appName;

  /// No description provided for @pro.
  ///
  /// In tr, this message translates to:
  /// **'PRO'**
  String get pro;

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
  /// **'Keşfet'**
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

  /// No description provided for @fieldLoginIdentifier.
  ///
  /// In tr, this message translates to:
  /// **'E-posta veya Kullanıcı Adı'**
  String get fieldLoginIdentifier;

  /// No description provided for @fieldLoginIdentifierHint.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen e-posta veya kullanıcı adınızı girin'**
  String get fieldLoginIdentifierHint;

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

  /// No description provided for @btnAddFavorite.
  ///
  /// In tr, this message translates to:
  /// **'Favorilere Ekle'**
  String get btnAddFavorite;

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

  /// No description provided for @errorNetworkTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı yok'**
  String get errorNetworkTitle;

  /// No description provided for @errorNetworkMessage.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantınızı kontrol edip tekrar deneyin.'**
  String get errorNetworkMessage;

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

  /// No description provided for @errorContentPolicy.
  ///
  /// In tr, this message translates to:
  /// **'İlan başlığı veya açıklaması topluluk kurallarına aykırı içerik barındırıyor.'**
  String get errorContentPolicy;

  /// No description provided for @similarListings.
  ///
  /// In tr, this message translates to:
  /// **'İlgilenebileceğin İlanlar'**
  String get similarListings;

  /// No description provided for @suggestedSellers.
  ///
  /// In tr, this message translates to:
  /// **'Önerilen Satıcılar'**
  String get suggestedSellers;

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

  /// No description provided for @giftSheetTitle.
  ///
  /// In tr, this message translates to:
  /// **'🎁 Hediye Gönder'**
  String get giftSheetTitle;

  /// No description provided for @giftNameFire.
  ///
  /// In tr, this message translates to:
  /// **'Ateş'**
  String get giftNameFire;

  /// No description provided for @giftNameDiamond.
  ///
  /// In tr, this message translates to:
  /// **'Elmas'**
  String get giftNameDiamond;

  /// No description provided for @giftNameCrown.
  ///
  /// In tr, this message translates to:
  /// **'Kral Tacı'**
  String get giftNameCrown;

  /// No description provided for @giftSentHud.
  ///
  /// In tr, this message translates to:
  /// **'🎉 {sender} hediye gönderdi!'**
  String giftSentHud(String sender);

  /// No description provided for @giftErrorGeneric.
  ///
  /// In tr, this message translates to:
  /// **'Hata oluştu.'**
  String get giftErrorGeneric;

  /// No description provided for @giftInsufficientBalance.
  ///
  /// In tr, this message translates to:
  /// **'Bakiyeniz yetersiz. Hediye göndermek için TUCi satın alın.'**
  String get giftInsufficientBalance;

  /// No description provided for @giftLoadBalanceButton.
  ///
  /// In tr, this message translates to:
  /// **'Bakiye Yükle'**
  String get giftLoadBalanceButton;

  /// No description provided for @purchaseLoadError.
  ///
  /// In tr, this message translates to:
  /// **'Alışverişleriniz yüklenirken bir sorun oluştu. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.'**
  String get purchaseLoadError;

  /// No description provided for @purchaseEmptyState.
  ///
  /// In tr, this message translates to:
  /// **'Henüz alışverişiniz bulunmuyor.'**
  String get purchaseEmptyState;

  /// No description provided for @purchaseUnknownItem.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Ürün'**
  String get purchaseUnknownItem;

  /// No description provided for @purchaseUnknownSeller.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Satıcı'**
  String get purchaseUnknownSeller;

  /// No description provided for @purchaseListingNotFound.
  ///
  /// In tr, this message translates to:
  /// **'İlan bulunamadı.'**
  String get purchaseListingNotFound;

  /// No description provided for @saleLoadError.
  ///
  /// In tr, this message translates to:
  /// **'Satışlarınız yüklenirken bir sorun oluştu. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.'**
  String get saleLoadError;

  /// No description provided for @saleEmptyState.
  ///
  /// In tr, this message translates to:
  /// **'Henüz satışınız bulunmuyor.'**
  String get saleEmptyState;

  /// No description provided for @saleUnknownBuyer.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Alıcı'**
  String get saleUnknownBuyer;

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

  /// No description provided for @msgGoToAuctionDetail.
  ///
  /// In tr, this message translates to:
  /// **'📋 Detaya Git →'**
  String get msgGoToAuctionDetail;

  /// No description provided for @msgTyping.
  ///
  /// In tr, this message translates to:
  /// **'yazıyor...'**
  String get msgTyping;

  /// No description provided for @msgUserFallback.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı'**
  String get msgUserFallback;

  /// No description provided for @msgItemFallback.
  ///
  /// In tr, this message translates to:
  /// **'Ürün'**
  String get msgItemFallback;

  /// No description provided for @msgContextPurchase.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş'**
  String get msgContextPurchase;

  /// No description provided for @msgContextSale.
  ///
  /// In tr, this message translates to:
  /// **'Satış'**
  String get msgContextSale;

  /// No description provided for @kbdTypingHint.
  ///
  /// In tr, this message translates to:
  /// **'Yazılıyor...'**
  String get kbdTypingHint;

  /// No description provided for @kbdDismiss.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get kbdDismiss;

  /// No description provided for @kbdConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Onayla'**
  String get kbdConfirm;

  /// No description provided for @kbdAmountHint.
  ///
  /// In tr, this message translates to:
  /// **'Tutar gir'**
  String get kbdAmountHint;

  /// No description provided for @voiceSwipeToCancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal için kaydır'**
  String get voiceSwipeToCancel;

  /// No description provided for @voicePermissionDenied.
  ///
  /// In tr, this message translates to:
  /// **'Mikrofon erişimi reddedildi. Ayarlar\'dan izin ver.'**
  String get voicePermissionDenied;

  /// No description provided for @voiceRecordFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt başlatılamadı'**
  String get voiceRecordFailed;

  /// No description provided for @voiceMaxDuration.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum 10 saniye'**
  String get voiceMaxDuration;

  /// No description provided for @voiceSendFailed.
  ///
  /// In tr, this message translates to:
  /// **'Ses mesajı gönderilemedi'**
  String get voiceSendFailed;

  /// No description provided for @voicePlayFailed.
  ///
  /// In tr, this message translates to:
  /// **'Ses oynatılamadı'**
  String get voicePlayFailed;

  /// No description provided for @attachPickGallery.
  ///
  /// In tr, this message translates to:
  /// **'Galeri'**
  String get attachPickGallery;

  /// No description provided for @attachPickCamera.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf Çek'**
  String get attachPickCamera;

  /// No description provided for @attachPickVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video Seç'**
  String get attachPickVideo;

  /// No description provided for @attachRecordVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video Çek'**
  String get attachRecordVideo;

  /// No description provided for @attachPickFile.
  ///
  /// In tr, this message translates to:
  /// **'Dosya'**
  String get attachPickFile;

  /// No description provided for @msgLastPhoto.
  ///
  /// In tr, this message translates to:
  /// **'📷 Fotoğraf'**
  String get msgLastPhoto;

  /// No description provided for @msgLastVideo.
  ///
  /// In tr, this message translates to:
  /// **'🎥 Video'**
  String get msgLastVideo;

  /// No description provided for @msgLastVoice.
  ///
  /// In tr, this message translates to:
  /// **'🎙 Ses mesajı'**
  String get msgLastVoice;

  /// No description provided for @msgLastFile.
  ///
  /// In tr, this message translates to:
  /// **'📎 Dosya'**
  String get msgLastFile;

  /// No description provided for @attachFileTooLarge.
  ///
  /// In tr, this message translates to:
  /// **'Dosya 5 MB\'dan büyük olamaz'**
  String get attachFileTooLarge;

  /// No description provided for @attachTypeNotSupported.
  ///
  /// In tr, this message translates to:
  /// **'Bu dosya türü desteklenmiyor'**
  String get attachTypeNotSupported;

  /// No description provided for @attachSendFailed.
  ///
  /// In tr, this message translates to:
  /// **'Dosya gönderilemedi'**
  String get attachSendFailed;

  /// No description provided for @attachOpenFailed.
  ///
  /// In tr, this message translates to:
  /// **'Dosya açılamadı'**
  String get attachOpenFailed;

  /// No description provided for @attachCameraPermission.
  ///
  /// In tr, this message translates to:
  /// **'Kamera erişimi reddedildi. Ayarlar\'dan izin ver.'**
  String get attachCameraPermission;

  /// No description provided for @attachGalleryPermission.
  ///
  /// In tr, this message translates to:
  /// **'Galeri erişimi reddedildi. Ayarlar\'dan izin ver.'**
  String get attachGalleryPermission;

  /// No description provided for @attachUploading.
  ///
  /// In tr, this message translates to:
  /// **'Yükleniyor...'**
  String get attachUploading;

  /// No description provided for @errFileTooLarge.
  ///
  /// In tr, this message translates to:
  /// **'Dosya çok büyük (maks. 5 MB)'**
  String get errFileTooLarge;

  /// No description provided for @errUnsupportedType.
  ///
  /// In tr, this message translates to:
  /// **'Desteklenmeyen dosya türü'**
  String get errUnsupportedType;

  /// No description provided for @errNetworkRetry.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı hatası. Tekrar dene.'**
  String get errNetworkRetry;

  /// No description provided for @liveStickerPicker.
  ///
  /// In tr, this message translates to:
  /// **'Stickerlar'**
  String get liveStickerPicker;

  /// No description provided for @attachVideoTooLong.
  ///
  /// In tr, this message translates to:
  /// **'Video 15 saniyeden uzun olamaz'**
  String get attachVideoTooLong;

  /// No description provided for @attachVideoProcessing.
  ///
  /// In tr, this message translates to:
  /// **'Video hazırlanıyor...'**
  String get attachVideoProcessing;

  /// No description provided for @msgDeleteMessage.
  ///
  /// In tr, this message translates to:
  /// **'Mesajı Sil'**
  String get msgDeleteMessage;

  /// No description provided for @msgDeleteMessageConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Bu mesajı silmek istediğine emin misin?'**
  String get msgDeleteMessageConfirm;

  /// No description provided for @msgDeleteMessageSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj silindi'**
  String get msgDeleteMessageSuccess;

  /// No description provided for @msgDeleteMessageFailed.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj silinemedi'**
  String get msgDeleteMessageFailed;

  /// No description provided for @msgDeleteConversation.
  ///
  /// In tr, this message translates to:
  /// **'Sohbeti Sil'**
  String get msgDeleteConversation;

  /// No description provided for @msgDeleteConversationConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Bu sohbeti silmek istediğine emin misin? Tüm mesajlar silinecek.'**
  String get msgDeleteConversationConfirm;

  /// No description provided for @msgDeleteConversationSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Sohbet silindi'**
  String get msgDeleteConversationSuccess;

  /// No description provided for @msgDeleteConversationFailed.
  ///
  /// In tr, this message translates to:
  /// **'Sohbet silinemedi'**
  String get msgDeleteConversationFailed;

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

  /// No description provided for @buyItNowAccepted.
  ///
  /// In tr, this message translates to:
  /// **'Hemen Al talebi onaylandı!'**
  String get buyItNowAccepted;

  /// No description provided for @errorPhotoCapture.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf çekilemedi.'**
  String get errorPhotoCapture;

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

  /// No description provided for @auctionBuyNowRequestSent.
  ///
  /// In tr, this message translates to:
  /// **'Talebiniz satıcıya iletildi, onay bekleniyor...'**
  String get auctionBuyNowRequestSent;

  /// No description provided for @auctionBuyNowOtherUser.
  ///
  /// In tr, this message translates to:
  /// **'⏳ Başka bir kullanıcı ile Hemen Al işlemi yapılıyor.'**
  String get auctionBuyNowOtherUser;

  /// No description provided for @auctionBuyNowAcceptInline.
  ///
  /// In tr, this message translates to:
  /// **'Onayla'**
  String get auctionBuyNowAcceptInline;

  /// No description provided for @auctionBuyNowRejectInline.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get auctionBuyNowRejectInline;

  /// No description provided for @errorInsufficientBalance.
  ///
  /// In tr, this message translates to:
  /// **'Bakiyeniz yetersiz. Lütfen bakiye yükleyin.'**
  String get errorInsufficientBalance;

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

  /// No description provided for @auctionBidReceived.
  ///
  /// In tr, this message translates to:
  /// **'₺{amount} teklifiniz alındı!'**
  String auctionBidReceived(String amount);

  /// No description provided for @chatJoinedStream.
  ///
  /// In tr, this message translates to:
  /// **'yayına katıldı'**
  String get chatJoinedStream;

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

  /// No description provided for @walletTxnSendGift.
  ///
  /// In tr, this message translates to:
  /// **'Canlı hediye gönderildi'**
  String get walletTxnSendGift;

  /// No description provided for @walletTxnReferralBonus.
  ///
  /// In tr, this message translates to:
  /// **'Davet ödülü'**
  String get walletTxnReferralBonus;

  /// No description provided for @walletTxnWelcomeBonus.
  ///
  /// In tr, this message translates to:
  /// **'Davet kodu bonusu'**
  String get walletTxnWelcomeBonus;

  /// No description provided for @walletTxnSpendRetargeting.
  ///
  /// In tr, this message translates to:
  /// **'Retargeting bildirimi'**
  String get walletTxnSpendRetargeting;

  /// No description provided for @walletTxnSpendBoost.
  ///
  /// In tr, this message translates to:
  /// **'Öne çıkarma'**
  String get walletTxnSpendBoost;

  /// No description provided for @walletTxnSpendBoostPaid.
  ///
  /// In tr, this message translates to:
  /// **'Öne çıkarma (ücretli)'**
  String get walletTxnSpendBoostPaid;

  /// No description provided for @walletTxnSpendReactivation.
  ///
  /// In tr, this message translates to:
  /// **'İlan yeniden yayına alma'**
  String get walletTxnSpendReactivation;

  /// No description provided for @walletSeeAllTxns.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü gör ({n} işlem)'**
  String walletSeeAllTxns(int n);

  /// No description provided for @walletAllTxnsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Tüm İşlemler'**
  String get walletAllTxnsTitle;

  /// No description provided for @walletDetailTitle.
  ///
  /// In tr, this message translates to:
  /// **'İşlem Detayı'**
  String get walletDetailTitle;

  /// No description provided for @walletDetailDate.
  ///
  /// In tr, this message translates to:
  /// **'Tarih'**
  String get walletDetailDate;

  /// No description provided for @walletDetailType.
  ///
  /// In tr, this message translates to:
  /// **'İşlem Türü'**
  String get walletDetailType;

  /// No description provided for @walletDetailAmount.
  ///
  /// In tr, this message translates to:
  /// **'Tutar'**
  String get walletDetailAmount;

  /// No description provided for @walletDetailListing.
  ///
  /// In tr, this message translates to:
  /// **'İlan'**
  String get walletDetailListing;

  /// No description provided for @walletDetailStream.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayın'**
  String get walletDetailStream;

  /// No description provided for @walletDetailListingInactive.
  ///
  /// In tr, this message translates to:
  /// **'Pasif ilan'**
  String get walletDetailListingInactive;

  /// No description provided for @walletDetailLoadingError.
  ///
  /// In tr, this message translates to:
  /// **'Detay yüklenemedi.'**
  String get walletDetailLoadingError;

  /// No description provided for @walletDetailGoListing.
  ///
  /// In tr, this message translates to:
  /// **'İlana Git'**
  String get walletDetailGoListing;

  /// No description provided for @walletDetailGoOwner.
  ///
  /// In tr, this message translates to:
  /// **'İlan Sahibi Profili'**
  String get walletDetailGoOwner;

  /// No description provided for @walletDetailGoStream.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Analizine Git'**
  String get walletDetailGoStream;

  /// No description provided for @walletDetailGoStreamHost.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Sahibi Profili'**
  String get walletDetailGoStreamHost;

  /// No description provided for @walletDetailGiftName.
  ///
  /// In tr, this message translates to:
  /// **'Hediye'**
  String get walletDetailGiftName;

  /// No description provided for @walletDetailGiftSender.
  ///
  /// In tr, this message translates to:
  /// **'Gönderen'**
  String get walletDetailGiftSender;

  /// No description provided for @walletDetailGiftReceiver.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı'**
  String get walletDetailGiftReceiver;

  /// No description provided for @walletDetailGiftStream.
  ///
  /// In tr, this message translates to:
  /// **'Yayın'**
  String get walletDetailGiftStream;

  /// No description provided for @walletDetailGiftHostShare.
  ///
  /// In tr, this message translates to:
  /// **'Alıcıya Geçen'**
  String get walletDetailGiftHostShare;

  /// No description provided for @walletDetailGoGiftSender.
  ///
  /// In tr, this message translates to:
  /// **'Gönderici Profili'**
  String get walletDetailGoGiftSender;

  /// No description provided for @walletDetailGoGiftReceiver.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı Profili'**
  String get walletDetailGoGiftReceiver;

  /// No description provided for @walletDetailGoGiftStream.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Analizine Git'**
  String get walletDetailGoGiftStream;

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

  /// No description provided for @proHubTabSales.
  ///
  /// In tr, this message translates to:
  /// **'Satış & Performans'**
  String get proHubTabSales;

  /// No description provided for @proHubTabMarket.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa & Rekabet'**
  String get proHubTabMarket;

  /// No description provided for @proHubTabAudience.
  ///
  /// In tr, this message translates to:
  /// **'Yayın & Kitle'**
  String get proHubTabAudience;

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
  /// **'👑 PRO Kullanıcı'**
  String get proStatusTitle;

  /// No description provided for @planMonthly.
  ///
  /// In tr, this message translates to:
  /// **'Aylık'**
  String get planMonthly;

  /// No description provided for @planYearly.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık'**
  String get planYearly;

  /// No description provided for @planLifetime.
  ///
  /// In tr, this message translates to:
  /// **'Ömür Boyu'**
  String get planLifetime;

  /// No description provided for @proStatusDesc.
  ///
  /// In tr, this message translates to:
  /// **'Tüm analitik araçlara erişiminiz aktif'**
  String get proStatusDesc;

  /// No description provided for @proRenewalDate.
  ///
  /// In tr, this message translates to:
  /// **'Yenileme: {date}'**
  String proRenewalDate(String date);

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

  /// No description provided for @proCreditsSummaryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kalan Krediler'**
  String get proCreditsSummaryTitle;

  /// No description provided for @proCreditsBlastName.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimi'**
  String get proCreditsBlastName;

  /// No description provided for @proCreditsBoostName.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkarılmış İlan'**
  String get proCreditsBoostName;

  /// No description provided for @proCreditsAiName.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Zeka Danışmanı'**
  String get proCreditsAiName;

  /// No description provided for @proCreditsReactivationName.
  ///
  /// In tr, this message translates to:
  /// **'Reaktivasyon'**
  String get proCreditsReactivationName;

  /// No description provided for @proCreditsBlastDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanınızı potansiyel alıcılara özel bildirimle duyurarak satış hızınızı artırır.'**
  String get proCreditsBlastDesc;

  /// No description provided for @proCreditsBoostDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanınızı listelemelerde en üste taşıyarak daha fazla görüntülenme almanızı sağlar.'**
  String get proCreditsBoostDesc;

  /// No description provided for @proCreditsAiDesc.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Zeka destekli algoritma ile ilanlarınıza en doğru piyasa fiyatı analizini yapar.'**
  String get proCreditsAiDesc;

  /// No description provided for @proCreditsReactivationDesc.
  ///
  /// In tr, this message translates to:
  /// **'Süresi dolmuş veya askıya alınmış ilanlarınızı ücretsiz olarak tekrar yayına almanızı sağlar.'**
  String get proCreditsReactivationDesc;

  /// No description provided for @proCreditsUsedFormat.
  ///
  /// In tr, this message translates to:
  /// **'{used} kullanıldı, {remaining} kaldı'**
  String proCreditsUsedFormat(int used, int remaining);

  /// No description provided for @proCreditsLimitFormat.
  ///
  /// In tr, this message translates to:
  /// **'{remaining} / {limit}'**
  String proCreditsLimitFormat(int remaining, int limit);

  /// No description provided for @blastConfirmCostFreeLabel.
  ///
  /// In tr, this message translates to:
  /// **'Ücret'**
  String get blastConfirmCostFreeLabel;

  /// No description provided for @blastConfirmCostPaidLabel.
  ///
  /// In tr, this message translates to:
  /// **'TUCi Maliyeti'**
  String get blastConfirmCostPaidLabel;

  /// No description provided for @blastSubtitleFree.
  ///
  /// In tr, this message translates to:
  /// **'Yayın başladığında push bildirim • Ücretsiz'**
  String get blastSubtitleFree;

  /// No description provided for @blastSubtitlePaid.
  ///
  /// In tr, this message translates to:
  /// **'Yayın başladığında push bildirim • {cost} TUCi'**
  String blastSubtitlePaid(int cost);

  /// No description provided for @blastConfirmCostFree.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz hakkınızdan düşülür'**
  String get blastConfirmCostFree;

  /// No description provided for @blastInviteDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'🎯 Kitleyi Davet Et'**
  String get blastInviteDialogTitle;

  /// No description provided for @blastTargetAudience.
  ///
  /// In tr, this message translates to:
  /// **'Hedef Kitle'**
  String get blastTargetAudience;

  /// No description provided for @blastNotificationLabel.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim'**
  String get blastNotificationLabel;

  /// No description provided for @blastNotificationValue.
  ///
  /// In tr, this message translates to:
  /// **'Push + Yayın linki'**
  String get blastNotificationValue;

  /// No description provided for @audienceReadyBuyersBanner.
  ///
  /// In tr, this message translates to:
  /// **'{count} Hazır Alıcıya Bildirim Gönder!'**
  String audienceReadyBuyersBanner(int count);

  /// No description provided for @blastBtnFree.
  ///
  /// In tr, this message translates to:
  /// **'{count} Hazır Alıcı — Bildirim Gönder (Ücretsiz)'**
  String blastBtnFree(int count);

  /// No description provided for @blastBtnPaid.
  ///
  /// In tr, this message translates to:
  /// **'{count} Hazır Alıcı — Bildirim Gönder ({cost} TUCi)'**
  String blastBtnPaid(int count, int cost);

  /// No description provided for @blastConfirmBodyFree.
  ///
  /// In tr, this message translates to:
  /// **'{count} hazır alıcıya bildirim gönderilecek.\n\nÜcretsiz toplu duyuru hakkınızdan düşülecek.'**
  String blastConfirmBodyFree(int count);

  /// No description provided for @blastConfirmBodyPaid.
  ///
  /// In tr, this message translates to:
  /// **'{count} hazır alıcıya bildirim gönderilecek.\n\nToplam ücret: {cost} TUCi'**
  String blastConfirmBodyPaid(int count, int cost);

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

  /// No description provided for @proSectionAIMetrics.
  ///
  /// In tr, this message translates to:
  /// **'AI Metrikler'**
  String get proSectionAIMetrics;

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
  /// **'Toplam Görüntülenme'**
  String get proFunnelViews;

  /// No description provided for @proFunnelHesitation.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Tereddüt'**
  String get proFunnelHesitation;

  /// No description provided for @proFunnelBid.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Teklif'**
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
  /// **'İlanlarınızın PRO ile Performansı'**
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
  /// **'gösterim'**
  String get metricViewed;

  /// No description provided for @metricClicked.
  ///
  /// In tr, this message translates to:
  /// **'tıkladı'**
  String get metricClicked;

  /// No description provided for @listingReach.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişi gördü'**
  String listingReach(int count);

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

  /// No description provided for @proToolCompetitorRadarTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rakip Fiyat Radarı'**
  String get proToolCompetitorRadarTitle;

  /// No description provided for @proToolCompetitorRadarDesc.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatın rakiplere kıyasla nerede? Kaçırdığın geliri gör.'**
  String get proToolCompetitorRadarDesc;

  /// No description provided for @proToolRetargetingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim Merkezi'**
  String get proToolRetargetingTitle;

  /// No description provided for @proToolRetargetingDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarınız ve canlı yayınlarınız için potansiyel alıcılara push bildirim gönderin ve raporları inceleyin.'**
  String get proToolRetargetingDesc;

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

  /// No description provided for @boostDialogPaidTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ücretli Öne Çıkar'**
  String get boostDialogPaidTitle;

  /// No description provided for @boostDialogPaidBadge.
  ///
  /// In tr, this message translates to:
  /// **'Bu ay {limit} ücretsiz hakkını kullandın'**
  String boostDialogPaidBadge(int limit);

  /// No description provided for @boostDialogPaidDesc.
  ///
  /// In tr, this message translates to:
  /// **'Ücretli boost ile ilanın yine \"Sana Özel\" akışında öne çıkarılır.'**
  String get boostDialogPaidDesc;

  /// No description provided for @boostDialogPaidCost.
  ///
  /// In tr, this message translates to:
  /// **'Maliyet'**
  String get boostDialogPaidCost;

  /// No description provided for @boostDialogPaidCostValue.
  ///
  /// In tr, this message translates to:
  /// **'50 TUCi'**
  String get boostDialogPaidCostValue;

  /// No description provided for @boostDialogPaidBalance.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Bakiyeniz'**
  String get boostDialogPaidBalance;

  /// No description provided for @boostDialogPaidConfirm.
  ///
  /// In tr, this message translates to:
  /// **'50 TUCi Öde ve Başlat'**
  String get boostDialogPaidConfirm;

  /// No description provided for @boostSuccessFree.
  ///
  /// In tr, this message translates to:
  /// **'🔥 İlanınız ücretsiz olarak öne çıkarıldı!'**
  String get boostSuccessFree;

  /// No description provided for @boostSuccessPaid.
  ///
  /// In tr, this message translates to:
  /// **'🔥 İlanınız öne çıkarıldı! (50 TUCi harcandı)'**
  String get boostSuccessPaid;

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

  /// No description provided for @boostErrorInsufficientTuci.
  ///
  /// In tr, this message translates to:
  /// **'Yetersiz TUCi bakiyesi. Ücretli boost için 50 TUCi gerekiyor.'**
  String get boostErrorInsufficientTuci;

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
  /// **'Harika! İlanınızı gören her 100 kişiden yaklaşık {clicks}\'i tıkladı — bu çok iyi bir ilgi oranı. İlan başlığı ve görseli alıcıları çekiyor.'**
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
  /// **'Benzer İlanların İlgi Oranı'**
  String get adMetricCategoryAvgCtr;

  /// No description provided for @softUpdateTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Sürüm Mevcut'**
  String get softUpdateTitle;

  /// No description provided for @softUpdateMessage.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamanın yeni bir sürümü yayınlandı. Daha iyi bir deneyim için hemen güncelleyebilirsiniz.'**
  String get softUpdateMessage;

  /// No description provided for @softUpdateUpdateNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi Güncelle'**
  String get softUpdateUpdateNow;

  /// No description provided for @softUpdateLater.
  ///
  /// In tr, this message translates to:
  /// **'Daha Sonra'**
  String get softUpdateLater;

  /// No description provided for @forgotPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi Unuttum'**
  String get forgotPassword;

  /// No description provided for @resetPasswordDescription.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen hesabınıza kayıtlı e-posta adresini girin.'**
  String get resetPasswordDescription;

  /// No description provided for @sendResetCode.
  ///
  /// In tr, this message translates to:
  /// **'Kodu Gönder'**
  String get sendResetCode;

  /// No description provided for @enterResetCode.
  ///
  /// In tr, this message translates to:
  /// **'E-postanıza gelen 6 haneli kodu girin'**
  String get enterResetCode;

  /// No description provided for @newPassword.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre'**
  String get newPassword;

  /// No description provided for @newPasswordConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre (Tekrar)'**
  String get newPasswordConfirm;

  /// No description provided for @passwordResetSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Şifreniz başarıyla sıfırlandı. Giriş yapabilirsiniz.'**
  String get passwordResetSuccess;

  /// No description provided for @settingsMyPurchases.
  ///
  /// In tr, this message translates to:
  /// **'Alışverişlerim'**
  String get settingsMyPurchases;

  /// No description provided for @noListingPhoto.
  ///
  /// In tr, this message translates to:
  /// **'İlan Fotoğrafı Yok'**
  String get noListingPhoto;

  /// No description provided for @purchaseDetailTitle.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş Detayı'**
  String get purchaseDetailTitle;

  /// No description provided for @purchaseSeller.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı'**
  String get purchaseSeller;

  /// No description provided for @purchaseProofImage.
  ///
  /// In tr, this message translates to:
  /// **'Satış Onay Görseli'**
  String get purchaseProofImage;

  /// No description provided for @purchaseViewListing.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Görüntüle'**
  String get purchaseViewListing;

  /// No description provided for @purchaseViewSeller.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı Profiline Git'**
  String get purchaseViewSeller;

  /// No description provided for @settingsMySales.
  ///
  /// In tr, this message translates to:
  /// **'Satışlarım'**
  String get settingsMySales;

  /// No description provided for @saleDetailTitle.
  ///
  /// In tr, this message translates to:
  /// **'Satış Detayı'**
  String get saleDetailTitle;

  /// No description provided for @saleBuyerLabel.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı'**
  String get saleBuyerLabel;

  /// No description provided for @saleMessageBuyer.
  ///
  /// In tr, this message translates to:
  /// **'Alıcıya Mesaj Gönder'**
  String get saleMessageBuyer;

  /// No description provided for @hostAcceptSaleDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'Satışı Onaylıyorsunuz'**
  String get hostAcceptSaleDialogTitle;

  /// No description provided for @hostAcceptSaleDialogBody.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen sattığınız ürünü kameraya gösterin ve onay fotoğrafını çekin.'**
  String get hostAcceptSaleDialogBody;

  /// No description provided for @hostAcceptSaleBtnCapture.
  ///
  /// In tr, this message translates to:
  /// **'Çek ve Onayla'**
  String get hostAcceptSaleBtnCapture;

  /// No description provided for @hostAcceptSaleBtnSkip.
  ///
  /// In tr, this message translates to:
  /// **'Çekmeden Onayla'**
  String get hostAcceptSaleBtnSkip;

  /// No description provided for @radarSuggestedCopied.
  ///
  /// In tr, this message translates to:
  /// **'{price} ₺ panoya kopyalandı'**
  String radarSuggestedCopied(String price);

  /// No description provided for @radarCopyBtn.
  ///
  /// In tr, this message translates to:
  /// **'Önerilen fiyatı kopyala: {price} ₺'**
  String radarCopyBtn(String price);

  /// No description provided for @retargetingBlastSent.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişiye bildirim gönderildi!'**
  String retargetingBlastSent(int count);

  /// No description provided for @notifSettingsBlastTitle.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimleri'**
  String get notifSettingsBlastTitle;

  /// No description provided for @notifSettingsBlastDesc.
  ///
  /// In tr, this message translates to:
  /// **'Kapalıyken push bildirim gelmez; bildirim listesinde görünmeye devam eder.'**
  String get notifSettingsBlastDesc;

  /// No description provided for @retargetingCooldownLabel.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar göndermek için:'**
  String get retargetingCooldownLabel;

  /// No description provided for @retargetingBlastCooldown.
  ///
  /// In tr, this message translates to:
  /// **'Bu ilan için bir sonraki toplu duyuruyu 24 saat sonra gönderebilirsiniz.'**
  String get retargetingBlastCooldown;

  /// No description provided for @retargetingDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim gönderilsin mi?'**
  String get retargetingDialogTitle;

  /// No description provided for @retargetingDialogBodyFree.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişiye \"Hâlâ ilgileniyor musun?\" bildirimi gönderilecek. {credits} bildirim krediniz var, ücretsiz gönderilecek.'**
  String retargetingDialogBodyFree(int count, int credits);

  /// No description provided for @retargetingDialogBodyPaid.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişiye \"Hâlâ ilgileniyor musun?\" bildirimi gönderilecek. Bunun karşılığında cüzdanından {cost} TUCi düşülecek.'**
  String retargetingDialogBodyPaid(int count, int cost);

  /// No description provided for @retargetingDialogBodyKarma.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişiye bildirim gönderilecek.\n\n{free} kredi kullanılacak + {cost} TUCi ödenecek.'**
  String retargetingDialogBodyKarma(int count, int free, int cost);

  /// No description provided for @retargetingDialogBodyInsufficient.
  ///
  /// In tr, this message translates to:
  /// **'Yetersiz TUCi bakiyesi.\nGerekli: {cost} TUCi | Mevcut: {balance} TUCi'**
  String retargetingDialogBodyInsufficient(int cost, int balance);

  /// No description provided for @retargetingCostFree.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz'**
  String get retargetingCostFree;

  /// No description provided for @retargetingCreditsLeft.
  ///
  /// In tr, this message translates to:
  /// **'{count} kredi kaldı'**
  String retargetingCreditsLeft(int count);

  /// No description provided for @retargetingFreeSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişi — 1 toplu duyuru krediniz kullanılır'**
  String retargetingFreeSubtitle(int count);

  /// No description provided for @retargetingPaidSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişi × 10 TUCi'**
  String retargetingPaidSubtitle(int count);

  /// No description provided for @retargetingEstimatedCost.
  ///
  /// In tr, this message translates to:
  /// **'Tahmini maliyet'**
  String get retargetingEstimatedCost;

  /// No description provided for @retargetingSending.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor...'**
  String get retargetingSending;

  /// No description provided for @retargetingSendBtnLabel.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişiye bildirim gönder'**
  String retargetingSendBtnLabel(int count);

  /// No description provided for @retargetingCreditsBadge.
  ///
  /// In tr, this message translates to:
  /// **'{count} kredi kaldı · ücretsiz gönderilir'**
  String retargetingCreditsBadge(int count);

  /// No description provided for @retargetingCostBadge.
  ///
  /// In tr, this message translates to:
  /// **'{cost} TUCi harcanır'**
  String retargetingCostBadge(int cost);

  /// No description provided for @retargetingFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcılar \"Hâlâ ilgileniyor musun?\" bildirimi alacak. Satın almayan kişilere gönderilir.'**
  String get retargetingFootnote;

  /// No description provided for @retargetingInfoText.
  ///
  /// In tr, this message translates to:
  /// **'İlanını daha önce görüntüleyen ama satın almayan kişilere hatırlatma bildirimi gönderir. Aylık toplu duyuru krediniz varsa ücretsiz, bitince her kişi için 10 TUCi harcanır.'**
  String get retargetingInfoText;

  /// No description provided for @retargetingLast30Days.
  ///
  /// In tr, this message translates to:
  /// **'Son 30 gün içinde'**
  String get retargetingLast30Days;

  /// No description provided for @retargetingViewerLabel.
  ///
  /// In tr, this message translates to:
  /// **'kişi gördü'**
  String get retargetingViewerLabel;

  /// No description provided for @retargetingBoughtLabel.
  ///
  /// In tr, this message translates to:
  /// **'satın aldı'**
  String get retargetingBoughtLabel;

  /// No description provided for @retargetingReachableLabel.
  ///
  /// In tr, this message translates to:
  /// **'ulaşılabilir'**
  String get retargetingReachableLabel;

  /// No description provided for @retargetingNoAudience.
  ///
  /// In tr, this message translates to:
  /// **'Şu an ulaşılabilecek kimse yok.'**
  String get retargetingNoAudience;

  /// No description provided for @retargetingNoAudienceDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanın daha fazla kişi tarafından görüntülenince burada kitlen oluşacak.'**
  String get retargetingNoAudienceDesc;

  /// No description provided for @retargetingNoListings.
  ///
  /// In tr, this message translates to:
  /// **'Aktif ilanın bulunamadı.'**
  String get retargetingNoListings;

  /// No description provided for @retargetingNoListingsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Retargeting için en az 1 aktif ilana ihtiyaç var.'**
  String get retargetingNoListingsDesc;

  /// No description provided for @errorGenericRetry.
  ///
  /// In tr, this message translates to:
  /// **'Bir hata oluştu, lütfen daha sonra tekrar deneyin.'**
  String get errorGenericRetry;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Doğrulama'**
  String get verifyEmailTitle;

  /// No description provided for @btnVerify.
  ///
  /// In tr, this message translates to:
  /// **'Doğrula'**
  String get btnVerify;

  /// No description provided for @btnResetPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi Sıfırla'**
  String get btnResetPassword;

  /// No description provided for @radarScreenTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rakip Radarı & Satış Hızı'**
  String get radarScreenTitle;

  /// No description provided for @priceMinLabel.
  ///
  /// In tr, this message translates to:
  /// **'{price} ₺ (min)'**
  String priceMinLabel(String price);

  /// No description provided for @priceMaxLabel.
  ///
  /// In tr, this message translates to:
  /// **'{price} ₺ (max)'**
  String priceMaxLabel(String price);

  /// No description provided for @forYouLabel.
  ///
  /// In tr, this message translates to:
  /// **'Sana Özel'**
  String get forYouLabel;

  /// No description provided for @messagesUpdateFailed.
  ///
  /// In tr, this message translates to:
  /// **'Güncellenemedi'**
  String get messagesUpdateFailed;

  /// No description provided for @staleDataBannerMessage.
  ///
  /// In tr, this message translates to:
  /// **'Veriler güncel olmayabilir'**
  String get staleDataBannerMessage;

  /// No description provided for @btnRefresh.
  ///
  /// In tr, this message translates to:
  /// **'Yenile'**
  String get btnRefresh;

  /// No description provided for @messagesLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Mesajlar yüklenemedi'**
  String get messagesLoadFailed;

  /// No description provided for @btnSend.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get btnSend;

  /// No description provided for @btnAcceptInvite.
  ///
  /// In tr, this message translates to:
  /// **'Kabul Et'**
  String get btnAcceptInvite;

  /// No description provided for @btnPin.
  ///
  /// In tr, this message translates to:
  /// **'Sabitle'**
  String get btnPin;

  /// No description provided for @retargetingBlastSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler başarıyla gönderildi!'**
  String get retargetingBlastSuccess;

  /// No description provided for @hostNotifDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim Gönder'**
  String get hostNotifDialogTitle;

  /// No description provided for @hostStreamDataError.
  ///
  /// In tr, this message translates to:
  /// **'Veri alınamadı'**
  String get hostStreamDataError;

  /// No description provided for @hostInviteError.
  ///
  /// In tr, this message translates to:
  /// **'Davet gönderilemedi: {error}'**
  String hostInviteError(String error);

  /// No description provided for @hostModRemoved.
  ///
  /// In tr, this message translates to:
  /// **'✖ @{username} moderatörlükten alındı'**
  String hostModRemoved(String username);

  /// No description provided for @genericErrorDetail.
  ///
  /// In tr, this message translates to:
  /// **'Hata: {error}'**
  String genericErrorDetail(String error);

  /// No description provided for @profilePhotoUploadError.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf yüklenemedi. Tekrar deneyin.'**
  String get profilePhotoUploadError;

  /// No description provided for @profileInviteCodeError.
  ///
  /// In tr, this message translates to:
  /// **'Davet kodu alınamadı, tekrar deneyin.'**
  String get profileInviteCodeError;

  /// No description provided for @profileInviteTitle.
  ///
  /// In tr, this message translates to:
  /// **'Arkadaşlarını Davet Et, TUCi Kazan!'**
  String get profileInviteTitle;

  /// No description provided for @profileInviteSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Her davet için +50, arkadaşın +10 TUCi kazanır'**
  String get profileInviteSubtitle;

  /// No description provided for @profileInviteShareText.
  ///
  /// In tr, this message translates to:
  /// **'Teqlif\'e katıl! Canlı mezat ve ikinci el alışverişin adresi 🎁\n\nKayıt olurken şu davet kodunu gir ve anında bonus TUCi kazan:\n\n🔑 Kod: {code}\n⏳ Son kullanım: {expiry} içinde\n\n📱 iOS App Store: apps.apple.com/app/teqlif\n🤖 Google Play: play.google.com/store/apps/details?id=com.teqlif.teqlif_mobile\n🌐 Web: teqlif.com'**
  String profileInviteShareText(String code, String expiry);

  /// No description provided for @profileInviteExpiryDays.
  ///
  /// In tr, this message translates to:
  /// **'{days} gün'**
  String profileInviteExpiryDays(int days);

  /// No description provided for @profileInviteExpiryHours.
  ///
  /// In tr, this message translates to:
  /// **'{hours} saat'**
  String profileInviteExpiryHours(int hours);

  /// No description provided for @profileInviteExpirySoon.
  ///
  /// In tr, this message translates to:
  /// **'kısa süre'**
  String get profileInviteExpirySoon;

  /// No description provided for @profileInviteCodeCopied.
  ///
  /// In tr, this message translates to:
  /// **'Kod kopyalandı!'**
  String get profileInviteCodeCopied;

  /// No description provided for @profileInviteModalExpiry.
  ///
  /// In tr, this message translates to:
  /// **'⏳ Son kullanım: {expiry} içinde'**
  String profileInviteModalExpiry(String expiry);

  /// No description provided for @profileInviteShareBtn.
  ///
  /// In tr, this message translates to:
  /// **'Daveti Paylaş'**
  String get profileInviteShareBtn;

  /// No description provided for @profilePickGallery.
  ///
  /// In tr, this message translates to:
  /// **'Galeriden Seç'**
  String get profilePickGallery;

  /// No description provided for @profilePickCamera.
  ///
  /// In tr, this message translates to:
  /// **'Kameradan Çek'**
  String get profilePickCamera;

  /// No description provided for @listingDeleteDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Sil'**
  String get listingDeleteDialogTitle;

  /// No description provided for @shareLinkCopied.
  ///
  /// In tr, this message translates to:
  /// **'Link kopyalandı'**
  String get shareLinkCopied;

  /// No description provided for @listingDeleteDialogBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu ilanı kalıcı olarak silmek istiyor musunuz?'**
  String get listingDeleteDialogBody;

  /// No description provided for @btnDeleteConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get btnDeleteConfirm;

  /// No description provided for @favoritesEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz favori ilan yok'**
  String get favoritesEmpty;

  /// No description provided for @createNeedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Önce ilan başlığını giriniz.'**
  String get createNeedTitle;

  /// No description provided for @aiPriceError.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat tahmini alınamadı. Lütfen tekrar deneyin.'**
  String get aiPriceError;

  /// No description provided for @tuciSpent.
  ///
  /// In tr, this message translates to:
  /// **'{count} TUCi harcandı.'**
  String tuciSpent(int count);

  /// No description provided for @videoTooLong.
  ///
  /// In tr, this message translates to:
  /// **'Video {max} saniyeyi geçemez ({actual}s).'**
  String videoTooLong(int max, int actual);

  /// No description provided for @createPickCamera.
  ///
  /// In tr, this message translates to:
  /// **'Kamera ile çek (maks {sec} sn)'**
  String createPickCamera(int sec);

  /// No description provided for @videoUploading.
  ///
  /// In tr, this message translates to:
  /// **'Video henüz yükleniyor, lütfen bekleyin.'**
  String get videoUploading;

  /// No description provided for @videoLabel.
  ///
  /// In tr, this message translates to:
  /// **'Video (maks {sec} sn)'**
  String videoLabel(int sec);

  /// No description provided for @forYouStreams.
  ///
  /// In tr, this message translates to:
  /// **'Sana Özel Yayınlar'**
  String get forYouStreams;

  /// No description provided for @searchNoResults.
  ///
  /// In tr, this message translates to:
  /// **'Sonuç bulunamadı'**
  String get searchNoResults;

  /// No description provided for @searchNoSupplyHint.
  ///
  /// In tr, this message translates to:
  /// **'Bu arama için şu an ilan az. Uyarı kur, yeni ilan gelince bildirim al.'**
  String get searchNoSupplyHint;

  /// No description provided for @searchCreateAlertBtn.
  ///
  /// In tr, this message translates to:
  /// **'Uyarı Kur'**
  String get searchCreateAlertBtn;

  /// No description provided for @proSearchCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} arama'**
  String proSearchCount(int count);

  /// No description provided for @listingDeactivateTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Pasife Al'**
  String get listingDeactivateTitle;

  /// No description provided for @listingDeactivateWarning.
  ///
  /// In tr, this message translates to:
  /// **'İlanı pasife alırsanız aktif vitrin/promosyon hakları silinir.'**
  String get listingDeactivateWarning;

  /// No description provided for @listingDeactivateCostHint.
  ///
  /// In tr, this message translates to:
  /// **'Uyarı: Ücretsiz 30 günlük pencere süreniz dolmuş. İlanı tekrar yayına almak için {cost} TUCi bakiyenizden düşülecektir.'**
  String listingDeactivateCostHint(int cost);

  /// No description provided for @listingDeactivateFreeCreditHint.
  ///
  /// In tr, this message translates to:
  /// **'Uyarı: Ücretsiz 30 günlük pencere süreniz dolmuş. İlanı tekrar yayına almak için 1 adet PRO ücretsiz hakkınız kullanılacaktır.'**
  String get listingDeactivateFreeCreditHint;

  /// No description provided for @listingDeactivateConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Anladım, Pasife Al'**
  String get listingDeactivateConfirm;

  /// No description provided for @listingReactivateTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Tekrar Yayınla'**
  String get listingReactivateTitle;

  /// No description provided for @listingReactivateFreeCredit.
  ///
  /// In tr, this message translates to:
  /// **'{remaining} ücretsiz hakkınız var. 1 hak kullanılacak.'**
  String listingReactivateFreeCredit(int remaining);

  /// No description provided for @listingReactivatePaidPro.
  ///
  /// In tr, this message translates to:
  /// **'Bu ayki hakkınız doldu. {cost} TUCi ödenecek.'**
  String listingReactivatePaidPro(int cost);

  /// No description provided for @listingReactivatePaidNormal.
  ///
  /// In tr, this message translates to:
  /// **'{cost} TUCi ödenecek. Bakiyeniz: {balance} TUCi.'**
  String listingReactivatePaidNormal(int cost, int balance);

  /// No description provided for @listingReactivateProUpsell.
  ///
  /// In tr, this message translates to:
  /// **'PRO\'ya geçerek ayda 5 ücretsiz hak kazanın.'**
  String get listingReactivateProUpsell;

  /// No description provided for @listingReactivateInsufficientBalance.
  ///
  /// In tr, this message translates to:
  /// **'Yetersiz bakiye. Devam etmek için TUCi yükleyin.'**
  String get listingReactivateInsufficientBalance;

  /// No description provided for @listingReactivateConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Aktif Yap'**
  String get listingReactivateConfirm;

  /// No description provided for @proReactivationSection.
  ///
  /// In tr, this message translates to:
  /// **'İlan Reaktivasyon Kredisi'**
  String get proReactivationSection;

  /// No description provided for @suggestedStreamers.
  ///
  /// In tr, this message translates to:
  /// **'Önerilen Yayıncılar'**
  String get suggestedStreamers;

  /// No description provided for @latestLiveStreams.
  ///
  /// In tr, this message translates to:
  /// **'En Son Canlı Yayınlar'**
  String get latestLiveStreams;

  /// No description provided for @categoryStreams.
  ///
  /// In tr, this message translates to:
  /// **'{category} Yayınları'**
  String categoryStreams(String category);

  /// No description provided for @listingsSelectedForYou.
  ///
  /// In tr, this message translates to:
  /// **'Sizin İçin Seçilen İlanlar'**
  String get listingsSelectedForYou;

  /// No description provided for @profileFaq.
  ///
  /// In tr, this message translates to:
  /// **'Sıkça Sorulan Sorular'**
  String get profileFaq;

  /// No description provided for @faqCatAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap İşlemleri, Profil ve Destek'**
  String get faqCatAccount;

  /// No description provided for @faqQAccountSignup.
  ///
  /// In tr, this message translates to:
  /// **'teqlif\'e nasıl kayıt olabilirim ve giriş yapabilirim?'**
  String get faqQAccountSignup;

  /// No description provided for @faqAAccountSignup.
  ///
  /// In tr, this message translates to:
  /// **'Ana sayfadaki \"Giriş Yap / Kayıt Ol\" butonunu kullanarak E-posta adresinizle saniyeler içinde hesabınızı oluşturabilir veya mevcut hesabınıza güvenle giriş yapabilirsiniz.'**
  String get faqAAccountSignup;

  /// No description provided for @faqQAccountEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresimi neden doğrulamalıyım?'**
  String get faqQAccountEmail;

  /// No description provided for @faqAAccountEmail.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınızın güvenliğini sağlamak ve şifre sıfırlama gibi kritik işlemleri yapabilmek için e-posta doğrulamanız zorunludur. Doğrulanmış e-postalar Mavi Tik ([ICON_VERIFIED]) (Onaylı Hesap) sürecinin de ilk adımıdır.'**
  String get faqAAccountEmail;

  /// No description provided for @faqQAccountProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profilimi nasıl düzenleyebilirim (İsim, Fotoğraf, Bio)?'**
  String get faqQAccountProfile;

  /// No description provided for @faqAAccountProfile.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama içerisinden \"Profilim\" sekmesine giderek Profili Düzenle butonuna tıklayabilirsiniz. Açılan ekranda profil fotoğrafınızı (avatar) değiştirebilir, ad-soyad bilgilerinizi güncelleyebilir ve potansiyel alıcıların sizi daha iyi tanıması için \"Hakkımda (Bio)\" kısmına kendinizi anlatan bir açıklama yazabilirsiniz.'**
  String get faqAAccountProfile;

  /// No description provided for @faqQAccountPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi unuttum, ne yapmalıyım?'**
  String get faqQAccountPassword;

  /// No description provided for @faqAAccountPassword.
  ///
  /// In tr, this message translates to:
  /// **'Giriş ekranındaki \"Şifremi Unuttum\" bağlantısına tıklayarak e-posta adresinize bir sıfırlama bağlantısı isteyebilir ve yeni şifrenizi belirleyebilirsiniz.'**
  String get faqAAccountPassword;

  /// No description provided for @faqQAccountDelete.
  ///
  /// In tr, this message translates to:
  /// **'Hesabımı nasıl silebilirim?'**
  String get faqQAccountDelete;

  /// No description provided for @faqAAccountDelete.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar > Hesabı Sil yolunu izleyerek hesabınızı kalıcı olarak silebilirsiniz. Bu işlem geri alınamaz; tüm verileriniz ve ilanlarınız sistemden kalıcı olarak kaldırılır.'**
  String get faqAAccountDelete;

  /// No description provided for @faqCatExplore.
  ///
  /// In tr, this message translates to:
  /// **'Keşif, Öneriler ve Menüler'**
  String get faqCatExplore;

  /// No description provided for @faqQExploreSellers.
  ///
  /// In tr, this message translates to:
  /// **'\"Önerilen Satıcılar\" bölümünde kimler yer alır?'**
  String get faqQExploreSellers;

  /// No description provided for @faqAExploreSellers.
  ///
  /// In tr, this message translates to:
  /// **'Bu liste yapay zeka algoritmamız tarafından otomatik belirlenir. Profilinde yüksek puanlama alan, ilanları sık ziyaret edilen, mesajlara hızlı yanıt veren ve genellikle PRO aboneliğine veya \"Güvenilir Satıcı\" rozetine sahip kullanıcılar burada sergilenerek platformdaki binlerce kişiye tavsiye edilir.'**
  String get faqAExploreSellers;

  /// No description provided for @faqQExploreStreamers.
  ///
  /// In tr, this message translates to:
  /// **'\"Önerilen Yayıncılar\" bölümü nasıl çalışır?'**
  String get faqQExploreStreamers;

  /// No description provided for @faqAExploreStreamers.
  ///
  /// In tr, this message translates to:
  /// **'SwipeLive platformunda düzenli olarak canlı yayın açan, yayınlarında yüksek \"Hype\" (Heyecan) puanına ulaşan ve aktif bir takipçi/izleyici kitlesine sahip yayıncılar sistem tarafından otomatik olarak Keşfet sayfasının en üstüne taşınır.'**
  String get faqAExploreStreamers;

  /// No description provided for @faqQExploreListings.
  ///
  /// In tr, this message translates to:
  /// **'\"İlanlar\" ve \"Keşfet\" sayfaları arasındaki fark nedir?'**
  String get faqQExploreListings;

  /// No description provided for @faqAExploreListings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlar sayfası yapay zekanın tamamen sizin ilgi alanlarınıza özel seçtiği ilanların ve en son eklenenlerin bulunduğu dikey bir akıştır. Keşfet sayfası ise; kategori bazlı detaylı aramalar yapabileceğiniz, popüler satıcı ve yayıncıları keşfedebileceğiniz ana arama merkezidir.'**
  String get faqAExploreListings;

  /// No description provided for @faqQExploreLiveMessages.
  ///
  /// In tr, this message translates to:
  /// **'\"Canlı\" ve \"Mesajlar\" menüleri ne işe yarar?'**
  String get faqQExploreLiveMessages;

  /// No description provided for @faqAExploreLiveMessages.
  ///
  /// In tr, this message translates to:
  /// **'Canlı: Satıcıların ürünlerini canlı yayında tanıttığı SwipeLive akışına ulaşmanızı sağlar. Mesajlar: İlgilendiğiniz ürünler için satıcılarla doğrudan sohbet edebilir ve güvenli bir şekilde fiyat pazarlığı (teklif) yapabilirsiniz.'**
  String get faqAExploreLiveMessages;

  /// No description provided for @faqCatBadges.
  ///
  /// In tr, this message translates to:
  /// **'Rozetler, Etiketler ve TUCi ([ICON_TUCI]) Kredisi'**
  String get faqCatBadges;

  /// No description provided for @faqQBadgesVerified.
  ///
  /// In tr, this message translates to:
  /// **'Mavi Tik ([ICON_VERIFIED]) (Doğrulanmış Hesap) nedir?'**
  String get faqQBadgesVerified;

  /// No description provided for @faqABadgesVerified.
  ///
  /// In tr, this message translates to:
  /// **'Mavi tik ([ICON_VERIFIED]), satıcının e-posta adresini ve telefon numarasını başarıyla doğruladığını gösterir. Bu rozet, potansiyel alıcılara sizin güvenilir bir gerçek kişi olduğunuzu kanıtlar.'**
  String get faqABadgesVerified;

  /// No description provided for @faqQBadgesPro.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarda gördüğüm \"👑 (Taç)\" rozeti nedir?'**
  String get faqQBadgesPro;

  /// No description provided for @faqABadgesPro.
  ///
  /// In tr, this message translates to:
  /// **'Bu rozet, ilanı paylaşan kullanıcının veya satıcının teqlif PRO ([ICON_PRO]) üyesi olduğunu gösterir. PRO satıcılar platform tarafından algoritmik olarak daha çok öne çıkarılan profesyonellerdir.'**
  String get faqABadgesPro;

  /// No description provided for @faqQBadgesTrusted.
  ///
  /// In tr, this message translates to:
  /// **'\"✅ Güvenilir\" ve \"⭐ Aktif\" Satıcı rozetleri ne anlama gelir?'**
  String get faqQBadgesTrusted;

  /// No description provided for @faqABadgesTrusted.
  ///
  /// In tr, this message translates to:
  /// **'✅ Güvenilir Satıcı: Kimlik bilgilerini doğrulamış, işlemleri sorunsuz tamamlanan ve platformda tam bir güven inşa etmiş deneyimli satıcılara verilir. ⭐ Aktif Satıcı: Platformu sık kullanan, alıcıların mesajlarına hızlı yanıt veren ve düzenli aralıklarla yeni ilanlar giren dinamik satıcıları temsil eder.'**
  String get faqABadgesTrusted;

  /// No description provided for @faqQBadgesSponsored.
  ///
  /// In tr, this message translates to:
  /// **'\"Sponsorlu\", \"Trending\" ve \"LIVE\" etiketleri neyi ifade eder?'**
  String get faqQBadgesSponsored;

  /// No description provided for @faqABadgesSponsored.
  ///
  /// In tr, this message translates to:
  /// **'Sponsorlu: Satıcının TUCi ([ICON_TUCI]) kredisi kullanarak ilanını öne çıkardığını belirtir. Trending (Ateş): İlanın son zamanlarda çok kişi tarafından incelendiğini veya favoriye eklendiğini (sıcak fırsat) gösterir. LIVE (Yanıp Sönen): Satıcının o an söz konusu ürün için canlı yayın (SwipeLive) yaptığını gösterir.'**
  String get faqABadgesSponsored;

  /// No description provided for @faqQBadgesTuci.
  ///
  /// In tr, this message translates to:
  /// **'TUCi ([ICON_TUCI]) nedir, nerelerde kullanılır?'**
  String get faqQBadgesTuci;

  /// No description provided for @faqABadgesTuci.
  ///
  /// In tr, this message translates to:
  /// **'TUCi ([ICON_TUCI]), teqlif içerisindeki sanal para/kredi birimimizdir. İlanlarınızı öne çıkarmak, canlı yayınlarda hediye göndermek, Yapay Zeka ile fiyat analizi yaptırmak ve \"Toplu Kitle Bildirimi ([ICON_HOTDEMAND])\" özelliğiyle doğrudan alıcılara ulaşmak için kullanılır.'**
  String get faqABadgesTuci;

  /// No description provided for @faqCatLive.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayınlar (SwipeLive) ve Açık Artırma'**
  String get faqCatLive;

  /// No description provided for @faqQLiveHost.
  ///
  /// In tr, this message translates to:
  /// **'Yayıncı (Host) ekranında neler yapabilirim?'**
  String get faqQLiveHost;

  /// No description provided for @faqALiveHost.
  ///
  /// In tr, this message translates to:
  /// **'Host ekranında sohbeti yönetebilir, ürününüz için Açık Artırma başlatabilir, gelen teklifleri (Bid) anlık görebilir ve sürenin sonunda en yüksek teklifi kabul edip satışı onaylayabilirsiniz.'**
  String get faqALiveHost;

  /// No description provided for @faqQLiveViewer.
  ///
  /// In tr, this message translates to:
  /// **'İzleyici (Viewer) ekranının özellikleri nelerdir?'**
  String get faqQLiveViewer;

  /// No description provided for @faqALiveViewer.
  ///
  /// In tr, this message translates to:
  /// **'Yayınları ekranı dikey olarak kaydırarak (SwipeLive) kesintisiz izleyebilirsiniz. Sohbete katılabilir, hediye gönderebilir ve açık artırmaya Canlı Teklif verebilirsiniz.'**
  String get faqALiveViewer;

  /// No description provided for @faqQLiveHype.
  ///
  /// In tr, this message translates to:
  /// **'Hype (Heyecan) seviyesi nedir?'**
  String get faqQLiveHype;

  /// No description provided for @faqALiveHype.
  ///
  /// In tr, this message translates to:
  /// **'İzleyiciler sohbete katıldıkça ve hediye gönderdikçe odanın Hype puanı artar. Puan limiti aştığında, yayın otomatik olarak \"Öne Çıkan Video (Highlight)\" kaydedilir.'**
  String get faqALiveHype;

  /// No description provided for @faqCatAI.
  ///
  /// In tr, this message translates to:
  /// **'PRO Araçları (Pro Tools) ve Yapay Zeka'**
  String get faqCatAI;

  /// No description provided for @faqQAIInsights.
  ///
  /// In tr, this message translates to:
  /// **'Dönüşüm Hunisi (Pro Insights) nedir?'**
  String get faqQAIInsights;

  /// No description provided for @faqAAIInsights.
  ///
  /// In tr, this message translates to:
  /// **'PRO satıcılara özel olan bu araç, ilanınızın görüntülenme sayısını, ziyaretçilerin ilan detayında geçirdiği süreyi ve tereddüt (hesitation) oranını raporlar.'**
  String get faqAAIInsights;

  /// No description provided for @faqQAIPrice.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Zeka Fiyat Tahmini (AI Price Intel) nasıl çalışır?'**
  String get faqQAIPrice;

  /// No description provided for @faqAAIPrice.
  ///
  /// In tr, this message translates to:
  /// **'Yapay zekamız ürününüzün başlığına ve kategorisine bakarak en hızlı satılabilecek optimum fiyatı size önerir.'**
  String get faqAAIPrice;

  /// No description provided for @faqQAILead.
  ///
  /// In tr, this message translates to:
  /// **'\"Toplu Kitle Bildirimi ([ICON_HOTDEMAND])\" özelliği nedir?'**
  String get faqQAILead;

  /// No description provided for @faqAAILead.
  ///
  /// In tr, this message translates to:
  /// **'İlanınıza en uygun potansiyel alıcıları yapay zeka ile eşleştirerek, doğrudan onlara \"Önerilen İlan\" bildirimi gönderen sistemdir.'**
  String get faqAAILead;

  /// No description provided for @faqQAIRadar.
  ///
  /// In tr, this message translates to:
  /// **'Rekabet Analizi ve En İyi Yayın Saati Tahmini'**
  String get faqQAIRadar;

  /// No description provided for @faqAAIRadar.
  ///
  /// In tr, this message translates to:
  /// **'Rekabet Analizi, ilanınızın fiyat durumunu ve tıklanma oranını rakiplerle kıyaslar. Yayın Saati Tahmini ise takipçilerinizin en aktif olduğu saatleri gösterir.'**
  String get faqAAIRadar;

  /// No description provided for @editListingTitle.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Düzenle'**
  String get editListingTitle;

  /// No description provided for @btnUpdate.
  ///
  /// In tr, this message translates to:
  /// **'Güncelle'**
  String get btnUpdate;

  /// No description provided for @btnUpdateListing.
  ///
  /// In tr, this message translates to:
  /// **'İlanı Güncelle'**
  String get btnUpdateListing;

  /// No description provided for @faqCatIcons.
  ///
  /// In tr, this message translates to:
  /// **'Sistem İkonları Sözlüğü'**
  String get faqCatIcons;

  /// No description provided for @faqIconVerified.
  ///
  /// In tr, this message translates to:
  /// **'Onaylı Hesap ([ICON_VERIFIED]): Kullanıcının kimliğini veya telefonunu doğruladığını gösterir.'**
  String get faqIconVerified;

  /// No description provided for @faqIconPro.
  ///
  /// In tr, this message translates to:
  /// **'teqlif PRO ([ICON_PRO]): Satıcının platform tarafından öne çıkarılan bir PRO üyesi olduğunu belirtir.'**
  String get faqIconPro;

  /// No description provided for @faqIconTuci.
  ///
  /// In tr, this message translates to:
  /// **'TUCi ([ICON_TUCI]): Sistem içi harcamalarda kullanılan sanal para birimidir.'**
  String get faqIconTuci;

  /// No description provided for @faqIconBlast.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimi ([ICON_BLAST]): İlanınızı/yayınınızı potansiyel alıcılara anlık push bildirim olarak yollar.'**
  String get faqIconBlast;

  /// No description provided for @faqIconAutoBid.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik Teklif ([ICON_AUTOBID]): Sistemin sizin adınıza belirlediğiniz limite kadar teklif vermesidir.'**
  String get faqIconAutoBid;

  /// No description provided for @faqIconSales.
  ///
  /// In tr, this message translates to:
  /// **'Satış İçgörüleri: Satış hacmi ve karlılık durumunuzu gösterir.'**
  String get faqIconSales;

  /// No description provided for @faqIconListings.
  ///
  /// In tr, this message translates to:
  /// **'İlan Analitikleri: İlanlarınızın görüntülenme ve favori metrikleridir.'**
  String get faqIconListings;

  /// No description provided for @faqIconMarket.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa İstihbaratı: Kategori bazlı piyasa fiyatları ve arz/talep eğilimleri.'**
  String get faqIconMarket;

  /// No description provided for @faqIconTime.
  ///
  /// In tr, this message translates to:
  /// **'En İyi Yayın Zamanı: Geçmiş verilere dayalı optimum yayın saati önerisi.'**
  String get faqIconTime;

  /// No description provided for @faqIconConversion.
  ///
  /// In tr, this message translates to:
  /// **'Dönüşüm Analizi: Görüntüleme başına elde edilen teklif ve satış hunisi.'**
  String get faqIconConversion;

  /// No description provided for @faqIconRadar.
  ///
  /// In tr, this message translates to:
  /// **'Rakip Radarı: Benzer satıcıların fiyat ve satış hızı analizleri.'**
  String get faqIconRadar;

  /// No description provided for @faqIconRetargeting.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden Hedefleme: İlgili alıcılara doğrudan hatırlatma veya indirim mesajı gönderimi.'**
  String get faqIconRetargeting;

  /// No description provided for @proToolHotDemandTitle.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimi'**
  String get proToolHotDemandTitle;

  /// No description provided for @proToolHotDemandDesc.
  ///
  /// In tr, this message translates to:
  /// **'İlanınızla ilgilenebilecek potansiyel alıcılara doğrudan ulaşın.'**
  String get proToolHotDemandDesc;

  /// No description provided for @proToolAiPriceTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Zeka Fiyat Analizi'**
  String get proToolAiPriceTitle;

  /// No description provided for @proToolAiPriceDesc.
  ///
  /// In tr, this message translates to:
  /// **'Ürününüzün piyasa değerini AI ile saniyeler içinde öğrenin.'**
  String get proToolAiPriceDesc;

  /// No description provided for @proToolStreamAnalyticsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yayın Analizi'**
  String get proToolStreamAnalyticsTitle;

  /// No description provided for @proToolStreamAnalyticsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Yayınlarınızdaki anlık izleyici ve hediye verilerini detaylı inceleyin.'**
  String get proToolStreamAnalyticsDesc;

  /// No description provided for @faqIconNameVerified.
  ///
  /// In tr, this message translates to:
  /// **'Onaylı Hesap'**
  String get faqIconNameVerified;

  /// No description provided for @faqIconNamePro.
  ///
  /// In tr, this message translates to:
  /// **'teqlif PRO ([ICON_PRO])'**
  String get faqIconNamePro;

  /// No description provided for @faqIconNameTuci.
  ///
  /// In tr, this message translates to:
  /// **'TUCi ([ICON_TUCI])'**
  String get faqIconNameTuci;

  /// No description provided for @faqIconNameBlast.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimi ([ICON_BLAST])'**
  String get faqIconNameBlast;

  /// No description provided for @faqIconNameAutoBid.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik Teklif ([ICON_AUTOBID])'**
  String get faqIconNameAutoBid;

  /// No description provided for @faqIconNameSales.
  ///
  /// In tr, this message translates to:
  /// **'Satış İçgörüleri'**
  String get faqIconNameSales;

  /// No description provided for @faqIconNameListings.
  ///
  /// In tr, this message translates to:
  /// **'İlan Analitikleri'**
  String get faqIconNameListings;

  /// No description provided for @faqIconNameMarket.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa İstihbaratı'**
  String get faqIconNameMarket;

  /// No description provided for @faqIconNameTime.
  ///
  /// In tr, this message translates to:
  /// **'En İyi Yayın Zamanı'**
  String get faqIconNameTime;

  /// No description provided for @faqIconNameConversion.
  ///
  /// In tr, this message translates to:
  /// **'Dönüşüm Analizi'**
  String get faqIconNameConversion;

  /// No description provided for @faqIconNameRadar.
  ///
  /// In tr, this message translates to:
  /// **'Rakip Radarı'**
  String get faqIconNameRadar;

  /// No description provided for @faqIconNameRetargeting.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden Hedefleme'**
  String get faqIconNameRetargeting;

  /// No description provided for @listingBlastEstimateLoading.
  ///
  /// In tr, this message translates to:
  /// **'Hedef kitle hesaplanıyor...'**
  String get listingBlastEstimateLoading;

  /// No description provided for @listingBlastDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimi'**
  String get listingBlastDialogTitle;

  /// No description provided for @listingBlastDialogBody.
  ///
  /// In tr, this message translates to:
  /// **'İlanınızla ilgilenebilecek potansiyel {count} kişi bulundu. Bu kişilere anında bildirim göndermek ister misiniz?'**
  String listingBlastDialogBody(int count);

  /// No description provided for @listingBlastCost.
  ///
  /// In tr, this message translates to:
  /// **'Maliyet: {cost} TUCi'**
  String listingBlastCost(int cost);

  /// No description provided for @reportMassNotificationTitle.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Bildirim Raporu'**
  String get reportMassNotificationTitle;

  /// No description provided for @reportMassNotificationDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu ekran, canlı yayınlarda ve ilan detaylarında gönderdiğiniz Toplu Kitle Bildirimlerinin dönüşüm istatistiklerini gösterir.'**
  String get reportMassNotificationDesc;

  /// No description provided for @reportLoadError.
  ///
  /// In tr, this message translates to:
  /// **'Rapor yüklenemedi: '**
  String get reportLoadError;

  /// No description provided for @reportNoNotificationYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz toplu bildirim göndermediniz.'**
  String get reportNoNotificationYet;

  /// No description provided for @centerNotificationAudience.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim & Kitle Merkezi'**
  String get centerNotificationAudience;

  /// No description provided for @reportTotalSpent.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Harcama:'**
  String get reportTotalSpent;

  /// No description provided for @reportCostPerClick.
  ///
  /// In tr, this message translates to:
  /// **'Tıklama Başı Maliyet:'**
  String get reportCostPerClick;

  /// No description provided for @reportConversionFunnel.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim Özeti'**
  String get reportConversionFunnel;

  /// No description provided for @reportAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get reportAll;

  /// No description provided for @reportFreeCreditsUsed.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz Hak:'**
  String get reportFreeCreditsUsed;

  /// No description provided for @reportTargetAudience.
  ///
  /// In tr, this message translates to:
  /// **'Hedeflenen Kitle'**
  String get reportTargetAudience;

  /// No description provided for @reportSuccessfullyDelivered.
  ///
  /// In tr, this message translates to:
  /// **'Başarıyla İletilen'**
  String get reportSuccessfullyDelivered;

  /// No description provided for @reportClickOpen.
  ///
  /// In tr, this message translates to:
  /// **'Tıklama (Açma)'**
  String get reportClickOpen;

  /// No description provided for @reportROI.
  ///
  /// In tr, this message translates to:
  /// **'Yatırım Getirisi (ROI)'**
  String get reportROI;

  /// No description provided for @actionConfirmAndStart.
  ///
  /// In tr, this message translates to:
  /// **'Onayla ve Başlat'**
  String get actionConfirmAndStart;

  /// No description provided for @auctionBuyNowRejected.
  ///
  /// In tr, this message translates to:
  /// **'Hemen Al talebi reddedildi.'**
  String get auctionBuyNowRejected;

  /// No description provided for @massAudienceNotification.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimi'**
  String get massAudienceNotification;

  /// No description provided for @actionSendMessageToSeller.
  ///
  /// In tr, this message translates to:
  /// **'Satıcıya Mesaj Gönder'**
  String get actionSendMessageToSeller;

  /// No description provided for @badgeVerified.
  ///
  /// In tr, this message translates to:
  /// **'Verified'**
  String get badgeVerified;

  /// No description provided for @titleActions.
  ///
  /// In tr, this message translates to:
  /// **'İşlemler'**
  String get titleActions;

  /// No description provided for @langTR.
  ///
  /// In tr, this message translates to:
  /// **'TR'**
  String get langTR;

  /// No description provided for @langEN.
  ///
  /// In tr, this message translates to:
  /// **'ENG'**
  String get langEN;

  /// No description provided for @langAR.
  ///
  /// In tr, this message translates to:
  /// **'عربي'**
  String get langAR;

  /// No description provided for @langRU.
  ///
  /// In tr, this message translates to:
  /// **'РУС'**
  String get langRU;

  /// No description provided for @kickedFromStream.
  ///
  /// In tr, this message translates to:
  /// **'🚫 Bu yayından atıldınız'**
  String get kickedFromStream;

  /// No description provided for @actionLeaveLiveStream.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayından Ayrıl'**
  String get actionLeaveLiveStream;

  /// No description provided for @streamNotificationAutoSent.
  ///
  /// In tr, this message translates to:
  /// **'Yayın başladığında bildirim otomatik gönderilir.'**
  String get streamNotificationAutoSent;

  /// No description provided for @proToolStreamHistoryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş Yayınlarım'**
  String get proToolStreamHistoryTitle;

  /// No description provided for @proToolStreamHistoryEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz tamamlanmış bir yayınınız yok.'**
  String get proToolStreamHistoryEmpty;

  /// No description provided for @analyticsRevenue.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Ciro'**
  String get analyticsRevenue;

  /// No description provided for @analyticsUniqueViewers.
  ///
  /// In tr, this message translates to:
  /// **'Tekil İzleyici'**
  String get analyticsUniqueViewers;

  /// No description provided for @analyticsAvgBudget.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama Bütçe'**
  String get analyticsAvgBudget;

  /// No description provided for @analyticsPeakViewers.
  ///
  /// In tr, this message translates to:
  /// **'Anlık Maksimum'**
  String get analyticsPeakViewers;

  /// No description provided for @analyticsHesitation.
  ///
  /// In tr, this message translates to:
  /// **'Tereddüt Sayısı'**
  String get analyticsHesitation;

  /// No description provided for @analyticsFeedImpressions.
  ///
  /// In tr, this message translates to:
  /// **'Akış Gösterimi'**
  String get analyticsFeedImpressions;

  /// No description provided for @analyticsFeedReach.
  ///
  /// In tr, this message translates to:
  /// **'Akış Erişimi'**
  String get analyticsFeedReach;

  /// No description provided for @analyticsAiRecommendation.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Zeka Önerisi'**
  String get analyticsAiRecommendation;

  /// No description provided for @analyticsNoAuctions.
  ///
  /// In tr, this message translates to:
  /// **'Bu yayında ihale açılmamış.'**
  String get analyticsNoAuctions;

  /// No description provided for @analyticsItemsSold.
  ///
  /// In tr, this message translates to:
  /// **'Satılan Ürünler'**
  String get analyticsItemsSold;

  /// No description provided for @analyticsDuration.
  ///
  /// In tr, this message translates to:
  /// **'{minutes} dk'**
  String analyticsDuration(int minutes);

  /// No description provided for @proToolStreamHistoryDesc.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş canlı yayınlarınızın satış ve izleyici istatistiklerini detaylı inceleyin.'**
  String get proToolStreamHistoryDesc;

  /// No description provided for @proTabSales.
  ///
  /// In tr, this message translates to:
  /// **'Performans'**
  String get proTabSales;

  /// No description provided for @proTabMarket.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa'**
  String get proTabMarket;

  /// No description provided for @proTabAudience.
  ///
  /// In tr, this message translates to:
  /// **'Kitle'**
  String get proTabAudience;

  /// No description provided for @listingVideoComplete.
  ///
  /// In tr, this message translates to:
  /// **'Video Tamamlandı'**
  String get listingVideoComplete;

  /// No description provided for @audienceTotalViewers.
  ///
  /// In tr, this message translates to:
  /// **'Toplam İzleyici'**
  String get audienceTotalViewers;

  /// No description provided for @searchHintTextListing.
  ///
  /// In tr, this message translates to:
  /// **'İlan başlığı veya açıklamasında ara...'**
  String get searchHintTextListing;

  /// No description provided for @filterTitle.
  ///
  /// In tr, this message translates to:
  /// **'Filtreler'**
  String get filterTitle;

  /// No description provided for @categoryLabel.
  ///
  /// In tr, this message translates to:
  /// **'Kategori'**
  String get categoryLabel;

  /// No description provided for @cityLabel.
  ///
  /// In tr, this message translates to:
  /// **'Şehir'**
  String get cityLabel;

  /// No description provided for @clearFilters.
  ///
  /// In tr, this message translates to:
  /// **'Temizle'**
  String get clearFilters;

  /// No description provided for @applyFilters.
  ///
  /// In tr, this message translates to:
  /// **'Uygula'**
  String get applyFilters;

  /// No description provided for @selectCity.
  ///
  /// In tr, this message translates to:
  /// **'Şehir Seçin'**
  String get selectCity;

  /// No description provided for @allCategories.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Kategoriler'**
  String get allCategories;

  /// No description provided for @filterAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get filterAll;

  /// No description provided for @filterSelectDate.
  ///
  /// In tr, this message translates to:
  /// **'Tarih Aralığı Seç'**
  String get filterSelectDate;

  /// No description provided for @hintExampleEmail.
  ///
  /// In tr, this message translates to:
  /// **'ornek@email.com'**
  String get hintExampleEmail;

  /// No description provided for @competitorRadarTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rakip Fiyat Radarı'**
  String get competitorRadarTitle;

  /// No description provided for @competitorRadarYourPrice.
  ///
  /// In tr, this message translates to:
  /// **'Senin fiyatın'**
  String get competitorRadarYourPrice;

  /// No description provided for @competitorRadarAvg.
  ///
  /// In tr, this message translates to:
  /// **'Rakip ort.'**
  String get competitorRadarAvg;

  /// No description provided for @competitorRadarSuggested.
  ///
  /// In tr, this message translates to:
  /// **'Önerilen'**
  String get competitorRadarSuggested;

  /// No description provided for @competitorRadarPercentile.
  ///
  /// In tr, this message translates to:
  /// **'Yüzdelik'**
  String get competitorRadarPercentile;

  /// No description provided for @competitorRadarDifference.
  ///
  /// In tr, this message translates to:
  /// **'Fark'**
  String get competitorRadarDifference;

  /// No description provided for @competitorRadarCompetitor.
  ///
  /// In tr, this message translates to:
  /// **'Rakip'**
  String get competitorRadarCompetitor;

  /// No description provided for @competitorRadarSalesSpeed.
  ///
  /// In tr, this message translates to:
  /// **'Satış Hızı'**
  String get competitorRadarSalesSpeed;

  /// No description provided for @competitorRadarSold.
  ///
  /// In tr, this message translates to:
  /// **'Satılan'**
  String get competitorRadarSold;

  /// No description provided for @competitorRadarActive.
  ///
  /// In tr, this message translates to:
  /// **'Aktif Rakip'**
  String get competitorRadarActive;

  /// No description provided for @competitorRadarSalePrice.
  ///
  /// In tr, this message translates to:
  /// **'Satış Fiyatı'**
  String get competitorRadarSalePrice;

  /// No description provided for @listingSuggestedStart.
  ///
  /// In tr, this message translates to:
  /// **'Önerilen Başlangıç'**
  String get listingSuggestedStart;

  /// No description provided for @listingExpectedClose.
  ///
  /// In tr, this message translates to:
  /// **'Beklenen Kapanış'**
  String get listingExpectedClose;

  /// No description provided for @listingLowest.
  ///
  /// In tr, this message translates to:
  /// **'En Düşük'**
  String get listingLowest;

  /// No description provided for @listingAverage.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama'**
  String get listingAverage;

  /// No description provided for @listingHighest.
  ///
  /// In tr, this message translates to:
  /// **'En Yüksek'**
  String get listingHighest;

  /// No description provided for @audienceCalculating.
  ///
  /// In tr, this message translates to:
  /// **'Kitle hesaplanıyor...'**
  String get audienceCalculating;

  /// No description provided for @audienceCalcError.
  ///
  /// In tr, this message translates to:
  /// **'Kitle hesaplanırken bir hata oluştu.'**
  String get audienceCalcError;

  /// No description provided for @audienceNoPotentialFound.
  ///
  /// In tr, this message translates to:
  /// **'Şu an bu ilanla ilgilenebilecek yeni potansiyel alıcı bulunamadı.'**
  String get audienceNoPotentialFound;

  /// No description provided for @audienceMassSendSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimi başarıyla gönderildi! 🚀'**
  String get audienceMassSendSuccess;

  /// No description provided for @audienceMassSendError.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim sırasında hata oluştu.'**
  String get audienceMassSendError;

  /// No description provided for @audienceSendToX.
  ///
  /// In tr, this message translates to:
  /// **'Belirli bir kişi sayısına gönder'**
  String get audienceSendToX;

  /// No description provided for @audiencePersonCountHint.
  ///
  /// In tr, this message translates to:
  /// **'Kişi sayısı'**
  String get audiencePersonCountHint;

  /// No description provided for @audienceNotificationWillGoTo.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim Gidecek:'**
  String get audienceNotificationWillGoTo;

  /// No description provided for @audienceMonthlyFreeRights.
  ///
  /// In tr, this message translates to:
  /// **'Aylık Ücretsiz Hak:'**
  String get audienceMonthlyFreeRights;

  /// No description provided for @audienceTotalCost.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Maliyet:'**
  String get audienceTotalCost;

  /// No description provided for @audienceInsufficientTuci.
  ///
  /// In tr, this message translates to:
  /// **'⚠️ Yetersiz TUCi bakiyesi, lütfen yükleme yapın.'**
  String get audienceInsufficientTuci;

  /// No description provided for @hostInvitedToStage.
  ///
  /// In tr, this message translates to:
  /// **'sahneye davet edildi'**
  String get hostInvitedToStage;

  /// No description provided for @hostModeration.
  ///
  /// In tr, this message translates to:
  /// **'Moderasyon'**
  String get hostModeration;

  /// No description provided for @hostMute.
  ///
  /// In tr, this message translates to:
  /// **'Sustur'**
  String get hostMute;

  /// No description provided for @hostUnmute.
  ///
  /// In tr, this message translates to:
  /// **'Susturmayı Kaldır'**
  String get hostUnmute;

  /// No description provided for @hostMakeModerator.
  ///
  /// In tr, this message translates to:
  /// **'Moderatör Yap'**
  String get hostMakeModerator;

  /// No description provided for @hostMadeModeratorMsg.
  ///
  /// In tr, this message translates to:
  /// **'moderatör yapıldı!'**
  String get hostMadeModeratorMsg;

  /// No description provided for @hostRemoveModerator.
  ///
  /// In tr, this message translates to:
  /// **'Moderatörlüğü Kaldır'**
  String get hostRemoveModerator;

  /// No description provided for @hostInviteToStage.
  ///
  /// In tr, this message translates to:
  /// **'Sahneye Davet Et'**
  String get hostInviteToStage;

  /// No description provided for @hostRemoveFromStage.
  ///
  /// In tr, this message translates to:
  /// **'Sahneden Al'**
  String get hostRemoveFromStage;

  /// No description provided for @hostKickFromStream.
  ///
  /// In tr, this message translates to:
  /// **'Yayından At'**
  String get hostKickFromStream;

  /// No description provided for @hostShowToAllViewersHint.
  ///
  /// In tr, this message translates to:
  /// **'Tüm izleyicilere gösterilecek...'**
  String get hostShowToAllViewersHint;

  /// No description provided for @swipeMutedInStream.
  ///
  /// In tr, this message translates to:
  /// **'Bu yayında susturuldunuz'**
  String get swipeMutedInStream;

  /// No description provided for @swipeMadeModeratorBy.
  ///
  /// In tr, this message translates to:
  /// **'sizi moderatör yaptı! Artık izleyicileri yönetebilirsiniz.'**
  String get swipeMadeModeratorBy;

  /// No description provided for @swipeRemovedFromStage.
  ///
  /// In tr, this message translates to:
  /// **'Sahneden kaldırıldınız'**
  String get swipeRemovedFromStage;

  /// No description provided for @swipeGiftSent.
  ///
  /// In tr, this message translates to:
  /// **'gönderildi! 🎉'**
  String get swipeGiftSent;

  /// No description provided for @notificationStart.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç'**
  String get notificationStart;

  /// No description provided for @notificationEnd.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş'**
  String get notificationEnd;

  /// No description provided for @proHubGotIt.
  ///
  /// In tr, this message translates to:
  /// **'Anladım'**
  String get proHubGotIt;

  /// No description provided for @profileSearchListingHint.
  ///
  /// In tr, this message translates to:
  /// **'İlan başlığı ara...'**
  String get profileSearchListingHint;

  /// No description provided for @profileFilterAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get profileFilterAll;

  /// No description provided for @profileInviteAndEarn.
  ///
  /// In tr, this message translates to:
  /// **'Davet Et & Kazan'**
  String get profileInviteAndEarn;

  /// No description provided for @publicProfileFollowers.
  ///
  /// In tr, this message translates to:
  /// **'Takipçiler'**
  String get publicProfileFollowers;

  /// No description provided for @publicProfileFollowing.
  ///
  /// In tr, this message translates to:
  /// **'Takip Edilenler'**
  String get publicProfileFollowing;

  /// No description provided for @publicProfileEditProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profili Düzenle'**
  String get publicProfileEditProfile;

  /// No description provided for @saleDetailGoToBuyer.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı Profiline Git'**
  String get saleDetailGoToBuyer;

  /// No description provided for @searchAiHint.
  ///
  /// In tr, this message translates to:
  /// **'Yapay zeka ile arayın (Örn: Vintage bir saat)'**
  String get searchAiHint;

  /// No description provided for @searchFilterUsers.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcılar'**
  String get searchFilterUsers;

  /// No description provided for @searchFilterListings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlar'**
  String get searchFilterListings;

  /// No description provided for @searchFilterStreams.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayınlar'**
  String get searchFilterStreams;

  /// No description provided for @auctionSendVerificationEmail.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama E-postası Gönder'**
  String get auctionSendVerificationEmail;

  /// No description provided for @storyTrayRecordVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video Çek'**
  String get storyTrayRecordVideo;

  /// No description provided for @storyTrayGalleryVideo.
  ///
  /// In tr, this message translates to:
  /// **'Galeriden Video'**
  String get storyTrayGalleryVideo;

  /// No description provided for @storyTrayTakePhoto.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf Çek'**
  String get storyTrayTakePhoto;

  /// No description provided for @storyTrayGalleryPhoto.
  ///
  /// In tr, this message translates to:
  /// **'Galeriden Fotoğraf'**
  String get storyTrayGalleryPhoto;

  /// No description provided for @phoneInputHint.
  ///
  /// In tr, this message translates to:
  /// **'Telefon numarası'**
  String get phoneInputHint;

  /// No description provided for @swipeListNoData.
  ///
  /// In tr, this message translates to:
  /// **'Veri bulunamadı.'**
  String get swipeListNoData;

  /// No description provided for @shareTitle.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş'**
  String get shareTitle;

  /// No description provided for @shareInstagramLabel.
  ///
  /// In tr, this message translates to:
  /// **'Instagram Story'**
  String get shareInstagramLabel;

  /// No description provided for @shareInstagramSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Story\'ne görsel olarak ekle'**
  String get shareInstagramSubtitle;

  /// No description provided for @shareWhatsAppLabel.
  ///
  /// In tr, this message translates to:
  /// **'WhatsApp'**
  String get shareWhatsAppLabel;

  /// No description provided for @shareWhatsAppSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Doğrudan WhatsApp\'a gönder'**
  String get shareWhatsAppSubtitle;

  /// No description provided for @shareCopyLabel.
  ///
  /// In tr, this message translates to:
  /// **'Link Kopyala'**
  String get shareCopyLabel;

  /// No description provided for @shareOtherLabel.
  ///
  /// In tr, this message translates to:
  /// **'Diğer...'**
  String get shareOtherLabel;

  /// No description provided for @shareOtherSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Tüm uygulamaları göster'**
  String get shareOtherSubtitle;

  /// No description provided for @emailWelcomeSub.
  ///
  /// In tr, this message translates to:
  /// **'Teqlif\'e Hoş Geldin!'**
  String get emailWelcomeSub;

  /// No description provided for @emailPhoneVerifySub.
  ///
  /// In tr, this message translates to:
  /// **'teqlif - Telefon Numaranızı Onaylayın'**
  String get emailPhoneVerifySub;

  /// No description provided for @emailVerifySub.
  ///
  /// In tr, this message translates to:
  /// **'teqlif - E-posta Doğrulama Kodu'**
  String get emailVerifySub;

  /// No description provided for @emailResetSub.
  ///
  /// In tr, this message translates to:
  /// **'teqlif - Şifre Sıfırlama Kodu'**
  String get emailResetSub;

  /// No description provided for @emailPhoneVerifyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Numarası Doğrulama'**
  String get emailPhoneVerifyTitle;

  /// No description provided for @emailHello.
  ///
  /// In tr, this message translates to:
  /// **'Merhaba'**
  String get emailHello;

  /// No description provided for @emailPhoneAdded.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınıza <strong style=\'font-size:18px;letter-spacing:1px\'>{phone}</strong> numarası eklendi. Bu numara size ait mi?'**
  String emailPhoneAdded(String phone);

  /// No description provided for @emailYesMine.
  ///
  /// In tr, this message translates to:
  /// **'✓ Evet, benimdir'**
  String get emailYesMine;

  /// No description provided for @emailNoNotMine.
  ///
  /// In tr, this message translates to:
  /// **'✗ Hayır, değil'**
  String get emailNoNotMine;

  /// No description provided for @emailLinkValid30m.
  ///
  /// In tr, this message translates to:
  /// **'Bu bağlantı <strong>30 dakika</strong> geçerlidir. Bu isteği siz yapmadıysanız yok sayabilirsiniz.'**
  String get emailLinkValid30m;

  /// No description provided for @emailSupport.
  ///
  /// In tr, this message translates to:
  /// **'Sorularınız için:'**
  String get emailSupport;

  /// No description provided for @emailVerifyBody.
  ///
  /// In tr, this message translates to:
  /// **'teqlif hesabınızı doğrulamak için aşağıdaki kodu kullanın:'**
  String get emailVerifyBody;

  /// No description provided for @emailCodeValid10m.
  ///
  /// In tr, this message translates to:
  /// **'Bu kod <strong>10 dakika</strong> geçerlidir.'**
  String get emailCodeValid10m;

  /// No description provided for @emailPhoneNote.
  ///
  /// In tr, this message translates to:
  /// **'📱 Kayıt sırasında telefon numarası girdiniz. Hesabınıza giriş yaptıktan sonra <strong style=\'color:#f1f5f9\'>Profil → Bilgilerim</strong> ekranından telefonunuzu doğrulayabilirsiniz.'**
  String get emailPhoneNote;

  /// No description provided for @emailResetBody.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınızın şifresini sıfırlamak için bir istekte bulunuldu. İşlemi tamamlamak için aşağıdaki kodu kullanın:'**
  String get emailResetBody;

  /// No description provided for @emailIgnoreIfNotYou.
  ///
  /// In tr, this message translates to:
  /// **'Bu isteği siz yapmadıysanız, e-postayı güvenle görmezden gelebilirsiniz.'**
  String get emailIgnoreIfNotYou;

  /// No description provided for @emailWelcomeHeroTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hoş geldin, {first_name}! 🎉'**
  String emailWelcomeHeroTitle(String first_name);

  /// No description provided for @emailWelcomeHeroSub.
  ///
  /// In tr, this message translates to:
  /// **'Canlı açık artırma dünyasına adım attın.<br>Harika fırsatlar seni bekliyor.'**
  String get emailWelcomeHeroSub;

  /// No description provided for @emailWelcomeIntro.
  ///
  /// In tr, this message translates to:
  /// **'Merhaba <strong style=\"color:#f1f5f9\">{full_name}</strong>,'**
  String emailWelcomeIntro(String full_name);

  /// No description provided for @emailWelcomeIntroBody.
  ///
  /// In tr, this message translates to:
  /// **'teqlif\'e katıldığın için çok mutluyuz. Artık canlı yayınlarda açık artırmalara katılabilir, favori yayıncıları takip edebilir ve eşsiz ürünlere teklif verebilirsin.'**
  String get emailWelcomeIntroBody;

  /// No description provided for @emailWelcomeF1Title.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayınlar'**
  String get emailWelcomeF1Title;

  /// No description provided for @emailWelcomeF1Sub.
  ///
  /// In tr, this message translates to:
  /// **'Yayıncıları keşfet, gerçek zamanlı artırmalara katıl'**
  String get emailWelcomeF1Sub;

  /// No description provided for @emailWelcomeF2Title.
  ///
  /// In tr, this message translates to:
  /// **'Anlık Teklifler'**
  String get emailWelcomeF2Title;

  /// No description provided for @emailWelcomeF2Sub.
  ///
  /// In tr, this message translates to:
  /// **'Saniyeler içinde teklif ver, yarışmayı kazan'**
  String get emailWelcomeF2Sub;

  /// No description provided for @emailWelcomeF3Title.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler & Takip'**
  String get emailWelcomeF3Title;

  /// No description provided for @emailWelcomeF3Sub.
  ///
  /// In tr, this message translates to:
  /// **'Beğendiğin yayıncıları takip et, bildirimleri al'**
  String get emailWelcomeF3Sub;

  /// No description provided for @emailWelcomePhoneTitle.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Doğrulaması'**
  String get emailWelcomePhoneTitle;

  /// No description provided for @emailWelcomePhoneNoBody.
  ///
  /// In tr, this message translates to:
  /// **'Yüksek tutarlı tekliflerde güvenli işlem yapabilmek için telefon numaranızı doğrulamanızı öneririz. Uygulamada <strong style=\"color:#e2e8f0\">Profil → Bilgilerim</strong> ekranından kolayca ekleyebilirsiniz.'**
  String get emailWelcomePhoneNoBody;

  /// No description provided for @emailWelcomePhoneYesBody.
  ///
  /// In tr, this message translates to:
  /// **'Telefon numaranızı kayıt sırasında eklediniz. Güvenli teklif verebilmek için <strong style=\"color:#e2e8f0\">Profil → Bilgilerim</strong> ekranından doğrulamayı tamamlayın.'**
  String get emailWelcomePhoneYesBody;

  /// No description provided for @emailWelcomeFooter.
  ///
  /// In tr, this message translates to:
  /// **'Sorularınız için her zaman buradayız.<br>Bize ulaşın: <a href=\"mailto:destek@teqlif.com\" style=\"color:#06b6d4;text-decoration:none\">destek@teqlif.com</a><br><strong style=\"color:#64748b\">teqlif ekibi</strong>'**
  String get emailWelcomeFooter;

  /// No description provided for @emailWelcomeCopyright.
  ///
  /// In tr, this message translates to:
  /// **'© 2025 teqlif · Bu e-postayı almak istemiyorsanız hesap ayarlarınızdan bildirim tercihlerinizi güncelleyebilirsiniz.'**
  String get emailWelcomeCopyright;

  /// No description provided for @emailResetGreeting.
  ///
  /// In tr, this message translates to:
  /// **'Merhaba <strong>{full_name}</strong>,'**
  String emailResetGreeting(String full_name);

  /// No description provided for @emailResetFooter.
  ///
  /// In tr, this message translates to:
  /// **'Sorularınız için: <a href=\'mailto:destek@teqlif.com\' style=\'color:#0d9488;text-decoration:none\'>destek@teqlif.com</a>'**
  String get emailResetFooter;

  /// No description provided for @fieldVerifyCode.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama Kodu'**
  String get fieldVerifyCode;

  /// No description provided for @authVerifyCodeSentMsg.
  ///
  /// In tr, this message translates to:
  /// **'Yeni doğrulama kodu {email} adresine gönderildi.'**
  String authVerifyCodeSentMsg(String email);

  /// No description provided for @authVerifyCodeSentDesc.
  ///
  /// In tr, this message translates to:
  /// **'{email} adresine 6 haneli doğrulama kodu gönderdik.'**
  String authVerifyCodeSentDesc(String email);

  /// No description provided for @authEnterCodeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kodunu gir'**
  String get authEnterCodeTitle;

  /// No description provided for @authVerifyCodeResent.
  ///
  /// In tr, this message translates to:
  /// **'Yeni doğrulama kodu gönderildi.'**
  String get authVerifyCodeResent;

  /// No description provided for @authResendCode.
  ///
  /// In tr, this message translates to:
  /// **'Kodu tekrar gönder'**
  String get authResendCode;

  /// No description provided for @validPasswordEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Şifre boş olamaz'**
  String get validPasswordEmpty;

  /// No description provided for @validPasswordConfirmEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Şifre tekrarı boş olamaz'**
  String get validPasswordConfirmEmpty;

  /// No description provided for @apiErrEmailFailed.
  ///
  /// In tr, this message translates to:
  /// **'E-posta gönderilemedi'**
  String get apiErrEmailFailed;

  /// No description provided for @apiErrEmailTaken.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta adresi zaten kullanılıyor'**
  String get apiErrEmailTaken;

  /// No description provided for @apiErrUsernameTaken.
  ///
  /// In tr, this message translates to:
  /// **'Bu kullanıcı adı zaten alınmış'**
  String get apiErrUsernameTaken;

  /// No description provided for @apiErrPhoneTaken.
  ///
  /// In tr, this message translates to:
  /// **'Bu telefon numarası zaten kayıtlı'**
  String get apiErrPhoneTaken;

  /// No description provided for @apiMsgRegisterSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt başarılı. E-posta adresinize doğrulama kodu gönderdik.'**
  String get apiMsgRegisterSuccess;

  /// No description provided for @apiErrCodeInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Kod hatalı veya süresi dolmuş'**
  String get apiErrCodeInvalid;

  /// No description provided for @apiErrUserNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı bulunamadı'**
  String get apiErrUserNotFound;

  /// No description provided for @apiErrInvalidCredentials.
  ///
  /// In tr, this message translates to:
  /// **'E-posta veya şifre hatalı'**
  String get apiErrInvalidCredentials;

  /// No description provided for @apiErrAccountDisabled.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınız devre dışı'**
  String get apiErrAccountDisabled;

  /// No description provided for @apiErrInvalidRequest.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz istek'**
  String get apiErrInvalidRequest;

  /// No description provided for @apiMsgCodeResent.
  ///
  /// In tr, this message translates to:
  /// **'Kod tekrar gönderildi'**
  String get apiMsgCodeResent;

  /// No description provided for @apiMsgResetEmailSent.
  ///
  /// In tr, this message translates to:
  /// **'Şifre sıfırlama e-postası gönderildi'**
  String get apiMsgResetEmailSent;

  /// No description provided for @apiErrEmailFailedLater.
  ///
  /// In tr, this message translates to:
  /// **'E-posta gönderilemedi, lütfen daha sonra tekrar deneyin.'**
  String get apiErrEmailFailedLater;

  /// No description provided for @apiErrCodeInvalidOrExpired.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz veya süresi dolmuş kod'**
  String get apiErrCodeInvalidOrExpired;

  /// No description provided for @apiMsgPasswordReset.
  ///
  /// In tr, this message translates to:
  /// **'Şifreniz başarıyla sıfırlandı'**
  String get apiMsgPasswordReset;

  /// No description provided for @apiErrNameShort.
  ///
  /// In tr, this message translates to:
  /// **'Ad soyad en az 2 karakter olmalı'**
  String get apiErrNameShort;

  /// No description provided for @apiErrUsernameFormat.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı 3-50 karakter, sadece küçük harf/rakam/alt çizgi'**
  String get apiErrUsernameFormat;

  /// No description provided for @apiErrBioLong.
  ///
  /// In tr, this message translates to:
  /// **'Biyografi en fazla 60 karakter olabilir'**
  String get apiErrBioLong;

  /// No description provided for @apiErrLinkFormat.
  ///
  /// In tr, this message translates to:
  /// **'Link http:// veya https:// ile başlamalı'**
  String get apiErrLinkFormat;

  /// No description provided for @apiErrAuctionNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Bu açık artırma bulunamadı veya erişim izniniz yok'**
  String get apiErrAuctionNotFound;

  /// No description provided for @apiErrTokenRequired.
  ///
  /// In tr, this message translates to:
  /// **'refresh_token gerekli'**
  String get apiErrTokenRequired;

  /// No description provided for @apiErrTokenInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz veya süresi dolmuş refresh token'**
  String get apiErrTokenInvalid;

  /// No description provided for @apiMsgLogout.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yapıldı'**
  String get apiMsgLogout;

  /// No description provided for @apiMsgVerifyEmailSent.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu e-posta adresinize gönderildi'**
  String get apiMsgVerifyEmailSent;

  /// No description provided for @apiErrCurrentPasswordInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut şifreniz hatalı'**
  String get apiErrCurrentPasswordInvalid;

  /// No description provided for @apiErrVerifyCodeInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu hatalı veya süresi dolmuş'**
  String get apiErrVerifyCodeInvalid;

  /// No description provided for @apiMsgPasswordChanged.
  ///
  /// In tr, this message translates to:
  /// **'Şifreniz başarıyla değiştirildi'**
  String get apiMsgPasswordChanged;

  /// No description provided for @apiErrEmailInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz e-posta adresi'**
  String get apiErrEmailInvalid;

  /// No description provided for @apiErrEmailSame.
  ///
  /// In tr, this message translates to:
  /// **'Bu zaten mevcut e-posta adresiniz'**
  String get apiErrEmailSame;

  /// No description provided for @apiErrEmailRetry.
  ///
  /// In tr, this message translates to:
  /// **'E-posta gönderilemedi, lütfen tekrar deneyin'**
  String get apiErrEmailRetry;

  /// No description provided for @apiMsgCodeSent.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu gönderildi'**
  String get apiMsgCodeSent;

  /// No description provided for @apiErrVerifyCodeNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu bulunamadı veya süresi doldu'**
  String get apiErrVerifyCodeNotFound;

  /// No description provided for @apiErrVerifyCodeWrong.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu hatalı'**
  String get apiErrVerifyCodeWrong;

  /// No description provided for @apiErrEmailMismatch.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresi eşleşmiyor'**
  String get apiErrEmailMismatch;

  /// No description provided for @apiErrEmailUsed.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta adresi başka bir hesapta kullanılıyor'**
  String get apiErrEmailUsed;

  /// No description provided for @apiMsgEmailUpdated.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresiniz başarıyla güncellendi'**
  String get apiMsgEmailUpdated;

  /// No description provided for @apiErrPhoneFormat.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz telefon numarası formatı'**
  String get apiErrPhoneFormat;

  /// No description provided for @apiErrPhoneUsed.
  ///
  /// In tr, this message translates to:
  /// **'Bu telefon numarası başka bir hesapta kayıtlı'**
  String get apiErrPhoneUsed;

  /// No description provided for @apiMsgVerifyEmailSent2.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama e-postası gönderildi'**
  String get apiMsgVerifyEmailSent2;

  /// No description provided for @errSomethingWentWrong.
  ///
  /// In tr, this message translates to:
  /// **'Bir hata oluştu'**
  String get errSomethingWentWrong;

  /// No description provided for @errAuthFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yetkilendirme hatası'**
  String get errAuthFailed;

  /// No description provided for @errStoryLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Hikaye yüklenemedi'**
  String get errStoryLoadFailed;

  /// No description provided for @errThumbnailLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Thumbnail yüklenemedi'**
  String get errThumbnailLoadFailed;

  /// No description provided for @btnAddListing.
  ///
  /// In tr, this message translates to:
  /// **'İlan Ekle'**
  String get btnAddListing;

  /// No description provided for @lblTuciWallet.
  ///
  /// In tr, this message translates to:
  /// **'TUCi Cüzdan'**
  String get lblTuciWallet;

  /// No description provided for @btnGoPro.
  ///
  /// In tr, this message translates to:
  /// **'Pro\'ya Geç'**
  String get btnGoPro;

  /// No description provided for @lblProNotificationSettings.
  ///
  /// In tr, this message translates to:
  /// **'Pro Bildirim Ayarları'**
  String get lblProNotificationSettings;

  /// No description provided for @lblStatusOff.
  ///
  /// In tr, this message translates to:
  /// **'Kapalı'**
  String get lblStatusOff;

  /// No description provided for @lblLoading.
  ///
  /// In tr, this message translates to:
  /// **'Yükleniyor...'**
  String get lblLoading;

  /// No description provided for @lblVideoReady.
  ///
  /// In tr, this message translates to:
  /// **'Video hazır'**
  String get lblVideoReady;

  /// No description provided for @lblListingUpper.
  ///
  /// In tr, this message translates to:
  /// **'İLAN'**
  String get lblListingUpper;

  /// No description provided for @btnGoToListing.
  ///
  /// In tr, this message translates to:
  /// **'İlana Git'**
  String get btnGoToListing;

  /// No description provided for @lblBidsUpper.
  ///
  /// In tr, this message translates to:
  /// **'TEKLİFLER'**
  String get lblBidsUpper;

  /// No description provided for @btnShareProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profili Paylaş'**
  String get btnShareProfile;

  /// No description provided for @lblNoListingsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz ilan yok'**
  String get lblNoListingsYet;

  /// No description provided for @timeJustNow.
  ///
  /// In tr, this message translates to:
  /// **'Az önce'**
  String get timeJustNow;

  /// No description provided for @timeNow.
  ///
  /// In tr, this message translates to:
  /// **'şimdi'**
  String get timeNow;

  /// No description provided for @timeMinAgo.
  ///
  /// In tr, this message translates to:
  /// **'{n}d önce'**
  String timeMinAgo(int n);

  /// No description provided for @timeHoursAgo.
  ///
  /// In tr, this message translates to:
  /// **'{n}s önce'**
  String timeHoursAgo(int n);

  /// No description provided for @timeDaysAgo.
  ///
  /// In tr, this message translates to:
  /// **'{n}g önce'**
  String timeDaysAgo(int n);

  /// No description provided for @radarExpensive.
  ///
  /// In tr, this message translates to:
  /// **'Pahalı'**
  String get radarExpensive;

  /// No description provided for @radarAffordable.
  ///
  /// In tr, this message translates to:
  /// **'Uygun fiyatlı'**
  String get radarAffordable;

  /// No description provided for @radarExpensivePrice.
  ///
  /// In tr, this message translates to:
  /// **'Pahalı fiyatlı'**
  String get radarExpensivePrice;

  /// No description provided for @radarExpensiveThanCompetitor.
  ///
  /// In tr, this message translates to:
  /// **'rakipten pahalı'**
  String get radarExpensiveThanCompetitor;

  /// No description provided for @radarCloseCompetitors.
  ///
  /// In tr, this message translates to:
  /// **'Yakın Rakipler'**
  String get radarCloseCompetitors;

  /// No description provided for @radarIn90Days.
  ///
  /// In tr, this message translates to:
  /// **'90 günde'**
  String get radarIn90Days;

  /// No description provided for @radarRightNow.
  ///
  /// In tr, this message translates to:
  /// **'şu an'**
  String get radarRightNow;

  /// No description provided for @btnStartNormal.
  ///
  /// In tr, this message translates to:
  /// **'Normal Başlat'**
  String get btnStartNormal;

  /// No description provided for @lblOther.
  ///
  /// In tr, this message translates to:
  /// **'diğer'**
  String get lblOther;

  /// No description provided for @btnViewNotificationReport.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim Raporunu Gör'**
  String get btnViewNotificationReport;

  /// No description provided for @btnSendMassNotification.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Kitle Bildirimi Gönder'**
  String get btnSendMassNotification;

  /// No description provided for @massNotifCooldownHours.
  ///
  /// In tr, this message translates to:
  /// **'{hours}s {min}dk sonra gönderilebilir'**
  String massNotifCooldownHours(int hours, int min);

  /// No description provided for @massNotifCooldownMinutes.
  ///
  /// In tr, this message translates to:
  /// **'{min}dk sonra gönderilebilir'**
  String massNotifCooldownMinutes(int min);

  /// No description provided for @massNotifCooldownSeconds.
  ///
  /// In tr, this message translates to:
  /// **'{sec}sn sonra gönderilebilir'**
  String massNotifCooldownSeconds(int sec);

  /// No description provided for @massNotifPerListingInfo.
  ///
  /// In tr, this message translates to:
  /// **'Her ilan için 24 saatte bir toplu bildirim gönderilebilir.'**
  String get massNotifPerListingInfo;

  /// No description provided for @btnShare.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş'**
  String get btnShare;

  /// No description provided for @shareListingText.
  ///
  /// In tr, this message translates to:
  /// **'{title} — teqlif\'te incele'**
  String shareListingText(Object title);

  /// No description provided for @shareLiveText.
  ///
  /// In tr, this message translates to:
  /// **'{title} — teqlif\'te canlı izle'**
  String shareLiveText(Object title);

  /// No description provided for @apiErrReferralUsed.
  ///
  /// In tr, this message translates to:
  /// **'Daha önce bir davet kodu kullandınız. Her hesap yalnızca bir kez kullanabilir.'**
  String get apiErrReferralUsed;

  /// No description provided for @apiErrReferralSelf.
  ///
  /// In tr, this message translates to:
  /// **'Kendi davet kodunuzu kullanamazsınız.'**
  String get apiErrReferralSelf;

  /// No description provided for @apiErrReferralInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz davet kodu. Lütfen kontrol edip tekrar deneyin.'**
  String get apiErrReferralInvalid;

  /// No description provided for @apiErrReferralExpired.
  ///
  /// In tr, this message translates to:
  /// **'Bu davet kodunun süresi dolmuş (3 günlük geçerlilik süresi bitmiş).'**
  String get apiErrReferralExpired;

  /// No description provided for @apiMsgReferralSavedVerify.
  ///
  /// In tr, this message translates to:
  /// **'Davet kodunuz kaydedildi! Ödül kazanmak için lütfen E-posta ve Telefon doğrulamanızı tamamlayın.'**
  String get apiMsgReferralSavedVerify;

  /// No description provided for @notifReferralTitle.
  ///
  /// In tr, this message translates to:
  /// **'Davet Ödülü!'**
  String get notifReferralTitle;

  /// No description provided for @notifReferralBody.
  ///
  /// In tr, this message translates to:
  /// **'Bir arkadaşınız ({username}) kodunuzu kullandı ve doğrulamasını tamamladı! {bonus} TUCi kazandınız.'**
  String notifReferralBody(String username, int bonus);

  /// No description provided for @apiMsgReferralSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulamalar tamamlandı! {referrer_username} sizi davet etti. Hesabınıza {your_bonus} TUCi eklendi.'**
  String apiMsgReferralSuccess(String referrer_username, int your_bonus);

  /// No description provided for @proTipPriceDownTitle.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Ayarı Önerisi'**
  String get proTipPriceDownTitle;

  /// No description provided for @proTipPriceDownBody.
  ///
  /// In tr, this message translates to:
  /// **'\"{title}\" piyasa ortalamasının %{diff} üzerinde. Fiyatı {avg} ₺ civarına çekersen satış hızlanabilir.'**
  String proTipPriceDownBody(Object avg, Object diff, Object title);

  /// No description provided for @proTipPriceUpTitle.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Artırma Fırsatı'**
  String get proTipPriceUpTitle;

  /// No description provided for @proTipPriceUpBody.
  ///
  /// In tr, this message translates to:
  /// **'\"{title}\" benzer ilanların %{diff} altında. Piyasa fiyatı {avg} ₺ — artırma fırsatı var.'**
  String proTipPriceUpBody(Object avg, Object diff, Object title);

  /// No description provided for @proTipLeadTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sıcak Alıcı Var'**
  String get proTipLeadTitle;

  /// No description provided for @proTipLeadBody.
  ///
  /// In tr, this message translates to:
  /// **'\"{title}\" için son 30 günde {count} kişi inceledi ama teklif vermedi. Fiyatı küçük düşür veya açıklama güçlendir.'**
  String proTipLeadBody(Object count, Object title);

  /// No description provided for @proTipStreamTitle.
  ///
  /// In tr, this message translates to:
  /// **'En İyi Yayın Saati'**
  String get proTipStreamTitle;

  /// No description provided for @proTipStreamBody.
  ///
  /// In tr, this message translates to:
  /// **'Platform genelinde en yoğun saat {hour}. Canlı yayını bu saatte başlatırsan daha fazla izleyiciye ulaşırsın.'**
  String proTipStreamBody(Object hour);

  /// No description provided for @proTipQualityTitle.
  ///
  /// In tr, this message translates to:
  /// **'Görsel & Açıklama İyileştir'**
  String get proTipQualityTitle;

  /// No description provided for @proTipQualityBody.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarının görüntülenme → teklif oranı %{pct}. Daha iyi fotoğraf ve detaylı açıklama bu oranı 3–5x artırabilir.'**
  String proTipQualityBody(Object pct);

  /// No description provided for @proTipAllGoodTitle.
  ///
  /// In tr, this message translates to:
  /// **'Her Şey Yolunda'**
  String get proTipAllGoodTitle;

  /// No description provided for @proTipAllGoodBody.
  ///
  /// In tr, this message translates to:
  /// **'İlan ve satış verilerin sağlıklı görünüyor. Daha fazla veri biriktiğinde özel öneriler burada belirecek.'**
  String get proTipAllGoodBody;

  /// No description provided for @notifNewBid.
  ///
  /// In tr, this message translates to:
  /// **'@{username} teklif verdi'**
  String notifNewBid(String username);

  /// No description provided for @notifNewBidBody.
  ///
  /// In tr, this message translates to:
  /// **'{item} — {price}'**
  String notifNewBidBody(String item, String price);

  /// No description provided for @notifNewBidBodyNoItem.
  ///
  /// In tr, this message translates to:
  /// **'{price}'**
  String notifNewBidBodyNoItem(String price);

  /// No description provided for @notifOutbid.
  ///
  /// In tr, this message translates to:
  /// **'Teklifiniz geçildi!'**
  String get notifOutbid;

  /// No description provided for @notifOutbidBody.
  ///
  /// In tr, this message translates to:
  /// **'{item} — yeni teklif: {price}'**
  String notifOutbidBody(String item, String price);

  /// No description provided for @notifOutbidBodyNoItem.
  ///
  /// In tr, this message translates to:
  /// **'Yeni teklif: {price}'**
  String notifOutbidBodyNoItem(String price);

  /// No description provided for @notifAuctionWon.
  ///
  /// In tr, this message translates to:
  /// **'🏆 Teklifiniz kabul edildi!'**
  String get notifAuctionWon;

  /// No description provided for @notifAuctionWonBody.
  ///
  /// In tr, this message translates to:
  /// **'{item} — {price}'**
  String notifAuctionWonBody(String item, String price);

  /// No description provided for @notifBuyItNow.
  ///
  /// In tr, this message translates to:
  /// **'🛒 Hemen Al tamamlandı!'**
  String get notifBuyItNow;

  /// No description provided for @notifBuyItNowBody.
  ///
  /// In tr, this message translates to:
  /// **'{item} — {price}'**
  String notifBuyItNowBody(String item, String price);

  /// No description provided for @notifAuctionEnded.
  ///
  /// In tr, this message translates to:
  /// **'Artırma sona erdi'**
  String get notifAuctionEnded;

  /// No description provided for @notifAuctionEndedBody.
  ///
  /// In tr, this message translates to:
  /// **'{item} — kazanan fiyat: {price}'**
  String notifAuctionEndedBody(String item, String price);

  /// No description provided for @notifAuctionEndedBodyNoItem.
  ///
  /// In tr, this message translates to:
  /// **'Kazanan fiyat: {price}'**
  String notifAuctionEndedBodyNoItem(String price);

  /// No description provided for @notifAuctionCancelled.
  ///
  /// In tr, this message translates to:
  /// **'Artırma iptal edildi'**
  String get notifAuctionCancelled;

  /// No description provided for @notifAuctionCancelledBody.
  ///
  /// In tr, this message translates to:
  /// **'{item} — teklif kabul edilmedi'**
  String notifAuctionCancelledBody(String item);

  /// No description provided for @notifAuctionCancelledBodyNoItem.
  ///
  /// In tr, this message translates to:
  /// **'Teklif kabul edilmedi'**
  String get notifAuctionCancelledBodyNoItem;

  /// No description provided for @notifStreamStarted.
  ///
  /// In tr, this message translates to:
  /// **'@{username} canlı yayın açtı'**
  String notifStreamStarted(String username);

  /// No description provided for @notifFollow.
  ///
  /// In tr, this message translates to:
  /// **'@{username} seni takip etmeye başladı'**
  String notifFollow(String username);

  /// No description provided for @notifMessage.
  ///
  /// In tr, this message translates to:
  /// **'@{username} size mesaj gönderdi'**
  String notifMessage(String username);

  /// No description provided for @notifMessageVoice.
  ///
  /// In tr, this message translates to:
  /// **'🎵 Ses mesajı'**
  String get notifMessageVoice;

  /// No description provided for @notifMessageImage.
  ///
  /// In tr, this message translates to:
  /// **'📷 Fotoğraf'**
  String get notifMessageImage;

  /// No description provided for @notifMessageVideo.
  ///
  /// In tr, this message translates to:
  /// **'🎬 Video'**
  String get notifMessageVideo;

  /// No description provided for @notifMessageFile.
  ///
  /// In tr, this message translates to:
  /// **'📎 Dosya'**
  String get notifMessageFile;

  /// No description provided for @notifNewListing.
  ///
  /// In tr, this message translates to:
  /// **'@{username} yeni ilan ekledi'**
  String notifNewListing(String username);

  /// No description provided for @notifListingDeactivated.
  ///
  /// In tr, this message translates to:
  /// **'İlanınız Pasife Alındı'**
  String get notifListingDeactivated;

  /// No description provided for @notifListingDeactivatedBodySingle.
  ///
  /// In tr, this message translates to:
  /// **'\"{title}\" adlı ilanınız 30 günlük süreyi doldurdu ve pasife alındı.'**
  String notifListingDeactivatedBodySingle(String title);

  /// No description provided for @notifListingDeactivatedBodyMultiple.
  ///
  /// In tr, this message translates to:
  /// **'{count} ilanınız 30 günlük süreyi doldurdu ve pasife alındı.'**
  String notifListingDeactivatedBodyMultiple(int count);

  /// No description provided for @notifListingDeleted.
  ///
  /// In tr, this message translates to:
  /// **'İlanınız Silindi'**
  String get notifListingDeleted;

  /// No description provided for @notifListingDeletedBodySingle.
  ///
  /// In tr, this message translates to:
  /// **'\"{title}\" adlı ilanınız sistemden kaldırıldı. Yeniden yayınlamak için yeni ilan oluşturabilirsiniz.'**
  String notifListingDeletedBodySingle(String title);

  /// No description provided for @notifListingDeletedBodyMultiple.
  ///
  /// In tr, this message translates to:
  /// **'{count} ilanınız sistemden kaldırıldı. Yeniden yayınlamak için yeni ilan oluşturabilirsiniz.'**
  String notifListingDeletedBodyMultiple(int count);

  /// No description provided for @notifListingRemoved.
  ///
  /// In tr, this message translates to:
  /// **'İlanınız kaldırıldı'**
  String get notifListingRemoved;

  /// No description provided for @notifListingRemovedBody.
  ///
  /// In tr, this message translates to:
  /// **'İlanınız topluluk kurallarına aykırı görsel içerik barındırdığı için yayından kaldırıldı.'**
  String get notifListingRemovedBody;

  /// No description provided for @notifSearchAlert.
  ///
  /// In tr, this message translates to:
  /// **'Arama alarmı: yeni ilan'**
  String get notifSearchAlert;

  /// No description provided for @notifSearchAlertBody.
  ///
  /// In tr, this message translates to:
  /// **'{category} kategorisinde yeni ürün eklendi'**
  String notifSearchAlertBody(String category);

  /// No description provided for @notifSmartAuctionAlert.
  ///
  /// In tr, this message translates to:
  /// **'Tam sana göre bir yayın başladı! 🎯'**
  String get notifSmartAuctionAlert;

  /// No description provided for @notifPriceDrop.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat düştü! 🔥'**
  String get notifPriceDrop;

  /// No description provided for @notifPriceDropBody.
  ///
  /// In tr, this message translates to:
  /// **'{item} — artık {price}'**
  String notifPriceDropBody(String item, String price);

  /// No description provided for @notifBudgetMatch.
  ///
  /// In tr, this message translates to:
  /// **'Bütçene uygun yeni ilan! 💡'**
  String get notifBudgetMatch;

  /// No description provided for @notifBudgetMatchBody.
  ///
  /// In tr, this message translates to:
  /// **'{item} — {price}'**
  String notifBudgetMatchBody(String item, String price);

  /// No description provided for @notifChurnAirdropSeller.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarınız sizi bekliyor! 🛍️'**
  String get notifChurnAirdropSeller;

  /// No description provided for @notifChurnBodySeller.
  ///
  /// In tr, this message translates to:
  /// **'Hesabına {amount} TUCi hediye yükledik. Yeni ilan aç, alıcılarla buluş!'**
  String notifChurnBodySeller(int amount);

  /// No description provided for @notifChurnAirdropBuyer.
  ///
  /// In tr, this message translates to:
  /// **'Seni özledik! 🎁'**
  String get notifChurnAirdropBuyer;

  /// No description provided for @notifChurnBodyBuyer.
  ///
  /// In tr, this message translates to:
  /// **'Hesabına {amount} TUCi hediye yükledik, hemen canlı yayınlara göz at ve harca!'**
  String notifChurnBodyBuyer(int amount);

  /// No description provided for @cat_elektronik.
  ///
  /// In tr, this message translates to:
  /// **'Elektronik'**
  String get cat_elektronik;

  /// No description provided for @cat_giyim.
  ///
  /// In tr, this message translates to:
  /// **'Giyim & Moda'**
  String get cat_giyim;

  /// No description provided for @cat_ev.
  ///
  /// In tr, this message translates to:
  /// **'Ev & Yaşam'**
  String get cat_ev;

  /// No description provided for @cat_vasita.
  ///
  /// In tr, this message translates to:
  /// **'Vasıta'**
  String get cat_vasita;

  /// No description provided for @cat_spor.
  ///
  /// In tr, this message translates to:
  /// **'Spor & Hobi'**
  String get cat_spor;

  /// No description provided for @cat_kitap.
  ///
  /// In tr, this message translates to:
  /// **'Kitap & Kültür'**
  String get cat_kitap;

  /// No description provided for @cat_emlak.
  ///
  /// In tr, this message translates to:
  /// **'Emlak'**
  String get cat_emlak;

  /// No description provided for @cat_diger.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get cat_diger;

  /// No description provided for @cat_sohbet.
  ///
  /// In tr, this message translates to:
  /// **'Sohbet'**
  String get cat_sohbet;

  /// No description provided for @day0.
  ///
  /// In tr, this message translates to:
  /// **'Pazar'**
  String get day0;

  /// No description provided for @day1.
  ///
  /// In tr, this message translates to:
  /// **'Pazartesi'**
  String get day1;

  /// No description provided for @day2.
  ///
  /// In tr, this message translates to:
  /// **'Salı'**
  String get day2;

  /// No description provided for @day3.
  ///
  /// In tr, this message translates to:
  /// **'Çarşamba'**
  String get day3;

  /// No description provided for @day4.
  ///
  /// In tr, this message translates to:
  /// **'Perşembe'**
  String get day4;

  /// No description provided for @day5.
  ///
  /// In tr, this message translates to:
  /// **'Cuma'**
  String get day5;

  /// No description provided for @day6.
  ///
  /// In tr, this message translates to:
  /// **'Cumartesi'**
  String get day6;

  /// No description provided for @recNoBudgetHighHesitation.
  ///
  /// In tr, this message translates to:
  /// **'Bugün {count} izleyici teklif vermekle ilgilendi ama tereddüt etti. Bir dahaki yayında daha düşük başlangıç fiyatıyla başlayarak ilgiyi satışa dönüştürebilirsiniz.'**
  String recNoBudgetHighHesitation(Object count);

  /// No description provided for @recNoBudgetDefault.
  ///
  /// In tr, this message translates to:
  /// **'Henüz yeterli bütçe verisi yok. Yayınlarınızı düzenli tutarak kitle profili oluştururken fiyat aralıklarını deneyebilirsiniz.'**
  String get recNoBudgetDefault;

  /// No description provided for @recHighHesitation.
  ///
  /// In tr, this message translates to:
  /// **'İzleyicilerinizin ortalama bütçesi {budget} TL. Bugün {count} kişi teklif vermek istedi ama vazgeçti — bir dahaki yayında {low} TL gibi düşük başlangıç fiyatları deneyerek bu kararsız kitleyi satışa çevirebilirsiniz.'**
  String recHighHesitation(Object budget, Object count, Object low);

  /// No description provided for @recMedHesitation.
  ///
  /// In tr, this message translates to:
  /// **'İzleyicilerinizin ortalama bütçesi {budget} TL. {count} izleyici tekliften vazgeçti — ürün açıklamalarını ve fiyat adımlarını netleştirerek dönüşüm oranınızı artırabilirsiniz.'**
  String recMedHesitation(Object budget, Object count);

  /// No description provided for @recHighReach.
  ///
  /// In tr, this message translates to:
  /// **'İzleyicilerinizin ortalama bütçesi {budget} TL. Kitle profiliniz güçlü görünüyor. Bir dahaki yayında {high} TL\'ye kadar premium ürünler sunarak geliri artırabilirsiniz.'**
  String recHighReach(Object budget, Object high);

  /// No description provided for @recDefault.
  ///
  /// In tr, this message translates to:
  /// **'İzleyicilerinizin ortalama bütçesi {budget} TL. Bu fiyat bandında ürünler getirerek satışlarınızı artırabilirsiniz.'**
  String recDefault(Object budget);

  /// No description provided for @radarCheap.
  ///
  /// In tr, this message translates to:
  /// **'Rakiplerin %{pct_rank}\'inden ucuzsun — fiyat artırabilirsin'**
  String radarCheap(Object pct_rank);

  /// No description provided for @radarFair.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatın piyasa ortalamasına yakın'**
  String get radarFair;

  /// No description provided for @errStreamNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Yayın bulunamadı'**
  String get errStreamNotFound;

  /// No description provided for @errAccessDenied.
  ///
  /// In tr, this message translates to:
  /// **'Bu rapora erişim yetkiniz yok'**
  String get errAccessDenied;

  /// No description provided for @errListingNotFound.
  ///
  /// In tr, this message translates to:
  /// **'İlan bulunamadı'**
  String get errListingNotFound;

  /// No description provided for @errProRequired.
  ///
  /// In tr, this message translates to:
  /// **'Bu özellik Pro kullanıcılara özeldir'**
  String get errProRequired;

  /// No description provided for @radarCheapLabel.
  ///
  /// In tr, this message translates to:
  /// **'Ucuz'**
  String get radarCheapLabel;

  /// No description provided for @radarFairLabel.
  ///
  /// In tr, this message translates to:
  /// **'Uygun'**
  String get radarFairLabel;

  /// No description provided for @proSalesSpeedTip.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa ortalamasının altında fiyatlanan ilanlar {ratio}× daha hızlı satılıyor'**
  String proSalesSpeedTip(Object ratio);

  /// No description provided for @proBestStreamRec.
  ///
  /// In tr, this message translates to:
  /// **'{day} {hours} saatlerinde %{rate} dönüşüm oranıyla en iyi performansı gösteriyorsunuz.'**
  String proBestStreamRec(Object day, Object hours, Object rate);

  /// No description provided for @tabReports.
  ///
  /// In tr, this message translates to:
  /// **'Raporlar'**
  String get tabReports;

  /// No description provided for @badgeSponsored.
  ///
  /// In tr, this message translates to:
  /// **'Sponsorlu'**
  String get badgeSponsored;

  /// No description provided for @aiPriceTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Zeka Fiyat Tahmini'**
  String get aiPriceTitle;

  /// No description provided for @aiPriceSimilar.
  ///
  /// In tr, this message translates to:
  /// **'{count} benzer ürün analiz edildi'**
  String aiPriceSimilar(int count);

  /// No description provided for @confidenceHigh.
  ///
  /// In tr, this message translates to:
  /// **'● Yüksek güven'**
  String get confidenceHigh;

  /// No description provided for @confidenceMedium.
  ///
  /// In tr, this message translates to:
  /// **'● Orta güven'**
  String get confidenceMedium;

  /// No description provided for @confidenceLow.
  ///
  /// In tr, this message translates to:
  /// **'● Düşük güven'**
  String get confidenceLow;

  /// No description provided for @aiPriceApply.
  ///
  /// In tr, this message translates to:
  /// **'Önerilen Fiyatı Uygula'**
  String get aiPriceApply;

  /// No description provided for @aiPriceAnalyzing.
  ///
  /// In tr, this message translates to:
  /// **'Analiz ediliyor…'**
  String get aiPriceAnalyzing;

  /// No description provided for @aiPriceButton.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Zeka ile Fiyat Belirle'**
  String get aiPriceButton;

  /// No description provided for @aiCreditsLeftSuffix.
  ///
  /// In tr, this message translates to:
  /// **'hak kaldı'**
  String get aiCreditsLeftSuffix;

  /// No description provided for @editProfileFullName.
  ///
  /// In tr, this message translates to:
  /// **'Ad Soyad'**
  String get editProfileFullName;

  /// No description provided for @editProfileUsername.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı Adı'**
  String get editProfileUsername;

  /// No description provided for @editProfileFillAll.
  ///
  /// In tr, this message translates to:
  /// **'Tüm alanları doldurun'**
  String get editProfileFillAll;

  /// No description provided for @aiAdviceSimilarCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} benzer ürün satış verisi analiz edildi'**
  String aiAdviceSimilarCount(int count);

  /// No description provided for @aiAdviceSameCategory.
  ///
  /// In tr, this message translates to:
  /// **'{count} aynı kategori'**
  String aiAdviceSameCategory(int count);

  /// No description provided for @aiAdviceCityBased.
  ///
  /// In tr, this message translates to:
  /// **'şehir bazlı'**
  String get aiAdviceCityBased;

  /// No description provided for @aiAdviceMarketClose.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama piyasa kapanışı: {price} ₺.'**
  String aiAdviceMarketClose(String price);

  /// No description provided for @aiAdviceBimodal.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün grubunda iki farklı piyasa fiyatı (Bimodal) tespit edildi. Ürününüzün varyasyonuna veya garantisine göre fiyat farklılaşabilir.'**
  String get aiAdviceBimodal;

  /// No description provided for @aiAdviceNoData.
  ///
  /// In tr, this message translates to:
  /// **'Henüz yeterli benzer ürün verisi bulunamadı. Platforma eklendikçe tahminler daha isabetli hale gelecek. Piyasa araştırması yaparak fiyatınızı belirleyebilirsiniz.'**
  String get aiAdviceNoData;

  /// No description provided for @proToolDemandTrendsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kategori Talep Trendi'**
  String get proToolDemandTrendsTitle;

  /// No description provided for @proToolDemandTrendsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Hangi kategoriler yükseliyor? Arz açığı olan fırsatları keşfet.'**
  String get proToolDemandTrendsDesc;

  /// No description provided for @demandTrendsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kategori Talep Trendi'**
  String get demandTrendsTitle;

  /// No description provided for @demandTrendsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Son 8 haftanın arama verisi'**
  String get demandTrendsSubtitle;

  /// No description provided for @demandTrendsUpLabel.
  ///
  /// In tr, this message translates to:
  /// **'Yükselen'**
  String get demandTrendsUpLabel;

  /// No description provided for @demandTrendsDownLabel.
  ///
  /// In tr, this message translates to:
  /// **'Düşen'**
  String get demandTrendsDownLabel;

  /// No description provided for @demandTrendsStableLabel.
  ///
  /// In tr, this message translates to:
  /// **'Sabit'**
  String get demandTrendsStableLabel;

  /// No description provided for @demandTrendsSupplyGapLabel.
  ///
  /// In tr, this message translates to:
  /// **'Arz Açığı'**
  String get demandTrendsSupplyGapLabel;

  /// No description provided for @demandTrendsSupplyGapHint.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcılar arıyor ama yeterli ilan yok'**
  String get demandTrendsSupplyGapHint;

  /// No description provided for @demandTrendsChangeLabel.
  ///
  /// In tr, this message translates to:
  /// **'%{pct} değişim (8 hafta)'**
  String demandTrendsChangeLabel(String pct);

  /// No description provided for @demandTrendsEmptyLabel.
  ///
  /// In tr, this message translates to:
  /// **'Henüz yeterli arama verisi yok.'**
  String get demandTrendsEmptyLabel;

  /// No description provided for @trustScoreLabel.
  ///
  /// In tr, this message translates to:
  /// **'Güven Skoru'**
  String get trustScoreLabel;

  /// No description provided for @trustScoreHint.
  ///
  /// In tr, this message translates to:
  /// **'0–100 arası platform güvenilirlik puanı. Açık artırma tamamlama oranı, kazanma geçmişi, ilan kalitesi, hesap yaşı ve teklif tutarlılığından hesaplanır. Her gece güncellenir.'**
  String get trustScoreHint;

  /// No description provided for @trustScoreLow.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Üye'**
  String get trustScoreLow;

  /// No description provided for @trustScoreMedium.
  ///
  /// In tr, this message translates to:
  /// **'Güvenilir'**
  String get trustScoreMedium;

  /// No description provided for @trustScoreHigh.
  ///
  /// In tr, this message translates to:
  /// **'Çok Güvenilir'**
  String get trustScoreHigh;

  /// No description provided for @influenceRankLabel.
  ///
  /// In tr, this message translates to:
  /// **'Ağ Sıralaması'**
  String get influenceRankLabel;

  /// No description provided for @influenceRankHint.
  ///
  /// In tr, this message translates to:
  /// **'Platformdaki takipçi ağına göre hesaplanan etki sıralaması. Ne kadar düşük numara, o kadar geniş erişim. Haftalık güncellenir.'**
  String get influenceRankHint;

  /// No description provided for @influenceRankValue.
  ///
  /// In tr, this message translates to:
  /// **'#{rank}. sıra'**
  String influenceRankValue(int rank);

  /// No description provided for @radarNoActiveListing.
  ///
  /// In tr, this message translates to:
  /// **'Aktif ilanın bulunamadı.'**
  String get radarNoActiveListing;

  /// No description provided for @radarNeedActiveListing.
  ///
  /// In tr, this message translates to:
  /// **'Rakip radarı için en az 1 aktif ilana ihtiyaç var.'**
  String get radarNeedActiveListing;

  /// No description provided for @radarNoPriceSet.
  ///
  /// In tr, this message translates to:
  /// **'Bu ilana fiyat girilmemiş.'**
  String get radarNoPriceSet;

  /// No description provided for @radarNoCompetitorData.
  ///
  /// In tr, this message translates to:
  /// **'Bu kategori için yeterli rakip verisi yok.'**
  String get radarNoCompetitorData;

  /// No description provided for @radarNo90DayData.
  ///
  /// In tr, this message translates to:
  /// **'Son 90 günde bu kategoride satış verisi yok.'**
  String get radarNo90DayData;

  /// No description provided for @radarVsAvgPrice.
  ///
  /// In tr, this message translates to:
  /// **'ort. fiyattan'**
  String get radarVsAvgPrice;

  /// No description provided for @radarActiveListings.
  ///
  /// In tr, this message translates to:
  /// **'aktif ilan'**
  String get radarActiveListings;

  /// No description provided for @radarDaysAvg.
  ///
  /// In tr, this message translates to:
  /// **'gün (ortalama)'**
  String get radarDaysAvg;

  /// No description provided for @radarDayRange.
  ///
  /// In tr, this message translates to:
  /// **'Aralık: {min} – {max} gün'**
  String radarDayRange(Object min, Object max);

  /// No description provided for @radarAverage.
  ///
  /// In tr, this message translates to:
  /// **'ortalama'**
  String get radarAverage;

  /// No description provided for @radarSweetSpotLabel.
  ///
  /// In tr, this message translates to:
  /// **'En çok satılan fiyat aralığı'**
  String get radarSweetSpotLabel;

  /// No description provided for @radarPriceSensitivity.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Hassasiyeti'**
  String get radarPriceSensitivity;

  /// No description provided for @radarDaySaleStat.
  ///
  /// In tr, this message translates to:
  /// **'{days} gün ({count} satış)'**
  String radarDaySaleStat(Object days, Object count);

  /// No description provided for @proNotEnoughStreamData.
  ///
  /// In tr, this message translates to:
  /// **'Henüz yeterli yayın verisi yok (min. 2 yayın gerekli).'**
  String get proNotEnoughStreamData;

  /// No description provided for @saleTypeBuyNow.
  ///
  /// In tr, this message translates to:
  /// **'Hemen Al'**
  String get saleTypeBuyNow;

  /// No description provided for @saleTypeBid.
  ///
  /// In tr, this message translates to:
  /// **'Teklif'**
  String get saleTypeBid;

  /// No description provided for @saleTypeAuction.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırma'**
  String get saleTypeAuction;

  /// No description provided for @saleStartPrice.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç Fiyatı'**
  String get saleStartPrice;

  /// No description provided for @saleType.
  ///
  /// In tr, this message translates to:
  /// **'Satış Türü'**
  String get saleType;

  /// No description provided for @saleBidCount.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Sayısı'**
  String get saleBidCount;

  /// No description provided for @notifProUpgradeTitle.
  ///
  /// In tr, this message translates to:
  /// **'👑 Pro Bildirim Ayarları'**
  String get notifProUpgradeTitle;

  /// No description provided for @notifProUpgradeDesc.
  ///
  /// In tr, this message translates to:
  /// **'Teklif eşiği ve sessiz saat ayarları Pro kullanıcılara özel.\nPro\'ya geçerek gereksiz bildirimlerden kurtulun.'**
  String get notifProUpgradeDesc;

  /// No description provided for @notifBidThresholdTitle.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Eşiği'**
  String get notifBidThresholdTitle;

  /// No description provided for @notifBidThresholdDesc.
  ///
  /// In tr, this message translates to:
  /// **'Sadece belirli tutarın üzerindeki teklifleri bildir'**
  String get notifBidThresholdDesc;

  /// No description provided for @notifQuietHoursTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sessiz Saatler'**
  String get notifQuietHoursTitle;

  /// No description provided for @notifQuietHoursDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu saatler arası bildirimleri ertele, sabah göster'**
  String get notifQuietHoursDesc;

  /// No description provided for @quickAuctionBtn.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı'**
  String get quickAuctionBtn;

  /// No description provided for @quickAuctionItem.
  ///
  /// In tr, this message translates to:
  /// **'Ürün {count}'**
  String quickAuctionItem(int count);

  /// No description provided for @quickAuctionStarted.
  ///
  /// In tr, this message translates to:
  /// **'Açık artırma başlatıldı'**
  String get quickAuctionStarted;

  /// No description provided for @phoneVerifyInvalidPhone.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir telefon numarası girin'**
  String get phoneVerifyInvalidPhone;

  /// No description provided for @phoneVerifyError.
  ///
  /// In tr, this message translates to:
  /// **'Bir hata oluştu'**
  String get phoneVerifyError;

  /// No description provided for @phoneVerifyConnectionError.
  ///
  /// In tr, this message translates to:
  /// **'Sunucuya bağlanılamadı'**
  String get phoneVerifyConnectionError;

  /// No description provided for @phoneVerifyEmailSentTitle.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Gönderildi'**
  String get phoneVerifyEmailSentTitle;

  /// No description provided for @phoneVerifyEmailSentDesc.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı e-posta adresinize doğrulama bağlantısı gönderdik. Lütfen gelen kutunuzu kontrol edin.'**
  String get phoneVerifyEmailSentDesc;

  /// No description provided for @phoneVerifyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Doğrulaması'**
  String get phoneVerifyTitle;

  /// No description provided for @phoneVerifyDesc.
  ///
  /// In tr, this message translates to:
  /// **'Yüksek tutarlı teklifler için telefon doğrulaması gerekiyor. Numaranızı girin, e-posta ile doğrulayın.'**
  String get phoneVerifyDesc;

  /// No description provided for @btnRemovePin.
  ///
  /// In tr, this message translates to:
  /// **'✕ Kaldır'**
  String get btnRemovePin;

  /// No description provided for @blastSent.
  ///
  /// In tr, this message translates to:
  /// **'🎯 {count} kişiye bildirim gönderildi!'**
  String blastSent(int count);

  /// No description provided for @blastStarted.
  ///
  /// In tr, this message translates to:
  /// **'🎯 Bildirim kampanyası başlatıldı!'**
  String get blastStarted;

  /// No description provided for @blastError.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim gönderilemedi.'**
  String get blastError;

  /// No description provided for @blastSending.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor…'**
  String get blastSending;

  /// No description provided for @hostRemoveFromStageBtn.
  ///
  /// In tr, this message translates to:
  /// **'✕ Sahneden Al'**
  String get hostRemoveFromStageBtn;

  /// No description provided for @hostViewersTitle.
  ///
  /// In tr, this message translates to:
  /// **'👁 İzleyiciler ({count})'**
  String hostViewersTitle(int count);

  /// No description provided for @auctionGroupFallback.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırma'**
  String get auctionGroupFallback;

  /// No description provided for @hostMuteSuccess.
  ///
  /// In tr, this message translates to:
  /// **'@{username} susturuldu'**
  String hostMuteSuccess(String username);

  /// No description provided for @hostUnmuteSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Susturma kaldırıldı'**
  String get hostUnmuteSuccess;

  /// No description provided for @hostPromoteSuccess.
  ///
  /// In tr, this message translates to:
  /// **'@{username} moderatör yapıldı'**
  String hostPromoteSuccess(String username);

  /// No description provided for @hostDemoteSuccess.
  ///
  /// In tr, this message translates to:
  /// **'@{username} moderatörlükten alındı'**
  String hostDemoteSuccess(String username);

  /// No description provided for @hostKickSuccess.
  ///
  /// In tr, this message translates to:
  /// **'@{username} yayından atıldı'**
  String hostKickSuccess(String username);

  /// No description provided for @whaleInRoom.
  ///
  /// In tr, this message translates to:
  /// **'{tier} Alıcı Odada'**
  String whaleInRoom(String tier);

  /// No description provided for @whaleShowBestItems.
  ///
  /// In tr, this message translates to:
  /// **'Kaliteli ürünleri çıkarma vakti!'**
  String get whaleShowBestItems;

  /// No description provided for @badgePassive.
  ///
  /// In tr, this message translates to:
  /// **'Pasif'**
  String get badgePassive;

  /// No description provided for @hesitatedSectionTitle.
  ///
  /// In tr, this message translates to:
  /// **'Geri Bak'**
  String get hesitatedSectionTitle;

  /// No description provided for @hesitatedSectionSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Vermek Üzereydin'**
  String get hesitatedSectionSubtitle;

  /// No description provided for @searchSmartResultsLabel.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Sonuçlar'**
  String get searchSmartResultsLabel;

  /// No description provided for @searchShowAllAccounts.
  ///
  /// In tr, this message translates to:
  /// **'Tüm hesapları gör ({count})'**
  String searchShowAllAccounts(int count);

  /// No description provided for @explorePersonalizedHint.
  ///
  /// In tr, this message translates to:
  /// **'Birkaç ilan incele,\nSana Özel içerik hazırlanıyor!'**
  String get explorePersonalizedHint;

  /// No description provided for @joinLiveStreamBanner.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayına Katıl →'**
  String get joinLiveStreamBanner;

  /// No description provided for @audienceCountPeople.
  ///
  /// In tr, this message translates to:
  /// **'{count} Kişi'**
  String audienceCountPeople(int count);

  /// No description provided for @audienceFreeSlots.
  ///
  /// In tr, this message translates to:
  /// **'-{count} Kişi'**
  String audienceFreeSlots(int count);

  /// No description provided for @defaultUserFallback.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı'**
  String get defaultUserFallback;

  /// No description provided for @startLiveStreamOption.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Yayın Aç'**
  String get startLiveStreamOption;

  /// No description provided for @noResultsFound.
  ///
  /// In tr, this message translates to:
  /// **'Sonuç bulunamadı'**
  String get noResultsFound;

  /// No description provided for @removeFromFavoritesTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Favoriden Çıkar'**
  String get removeFromFavoritesTooltip;

  /// No description provided for @callVoiceCall.
  ///
  /// In tr, this message translates to:
  /// **'Sesli Arama'**
  String get callVoiceCall;

  /// No description provided for @callCalling.
  ///
  /// In tr, this message translates to:
  /// **'Arıyor...'**
  String get callCalling;

  /// No description provided for @callConnecting.
  ///
  /// In tr, this message translates to:
  /// **'Bağlanıyor...'**
  String get callConnecting;

  /// No description provided for @callConnected.
  ///
  /// In tr, this message translates to:
  /// **'Bağlandı'**
  String get callConnected;

  /// No description provided for @callEnded.
  ///
  /// In tr, this message translates to:
  /// **'Arama Bitti'**
  String get callEnded;

  /// No description provided for @callRejected.
  ///
  /// In tr, this message translates to:
  /// **'Arama Reddedildi'**
  String get callRejected;

  /// No description provided for @callMissed.
  ///
  /// In tr, this message translates to:
  /// **'Cevapsız Arama'**
  String get callMissed;

  /// No description provided for @callNoAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Cevap Verilmedi'**
  String get callNoAnswer;

  /// No description provided for @callAccept.
  ///
  /// In tr, this message translates to:
  /// **'Kabul Et'**
  String get callAccept;

  /// No description provided for @callDecline.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get callDecline;

  /// No description provided for @callMute.
  ///
  /// In tr, this message translates to:
  /// **'Sessiz'**
  String get callMute;

  /// No description provided for @callUnmute.
  ///
  /// In tr, this message translates to:
  /// **'Sesi Aç'**
  String get callUnmute;

  /// No description provided for @callSpeaker.
  ///
  /// In tr, this message translates to:
  /// **'Hoparlör'**
  String get callSpeaker;

  /// No description provided for @callIncomingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Gelen Arama'**
  String get callIncomingTitle;

  /// No description provided for @callIncomingBody.
  ///
  /// In tr, this message translates to:
  /// **'@{username} arıyor'**
  String callIncomingBody(String username);

  /// No description provided for @callReturnToActive.
  ///
  /// In tr, this message translates to:
  /// **'Aramaya dönmek için dokunun'**
  String get callReturnToActive;

  /// No description provided for @callNotifAccept.
  ///
  /// In tr, this message translates to:
  /// **'Cevapla'**
  String get callNotifAccept;

  /// No description provided for @callNotifDecline.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get callNotifDecline;

  /// No description provided for @callPermissionDenied.
  ///
  /// In tr, this message translates to:
  /// **'Mikrofon izni gerekli'**
  String get callPermissionDenied;

  /// No description provided for @callVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video'**
  String get callVideo;

  /// No description provided for @callChat.
  ///
  /// In tr, this message translates to:
  /// **'Sohbet'**
  String get callChat;

  /// No description provided for @callAddPerson.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get callAddPerson;

  /// No description provided for @notifCallMissed.
  ///
  /// In tr, this message translates to:
  /// **'Cevapsız Arama: @{username}'**
  String notifCallMissed(String username);

  /// No description provided for @notifCallMissedBody.
  ///
  /// In tr, this message translates to:
  /// **'Size ulaşmaya çalıştı.'**
  String get notifCallMissedBody;

  /// Incoming call push notification title
  ///
  /// In tr, this message translates to:
  /// **'@{username} sizi arıyor'**
  String callNotifTitle(String username);

  /// Incoming call push notification body
  ///
  /// In tr, this message translates to:
  /// **'Gelen Sesli Arama'**
  String get callNotifBody;
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
      <String>['ar', 'en', 'ru', 'tr'].contains(locale.languageCode);

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
    case 'ru':
      return AppLocalizationsRu();
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
