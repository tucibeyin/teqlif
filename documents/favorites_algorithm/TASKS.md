# Favorileme ve Beğeni Senkronizasyon Mimarisi - GÖREV / TAKİP LİSTESİ (TASKS)

Bu kontrol listesi, `PLAN.md` dokümanında detaylandırılan endüstri standardı senkronizasyon mimarisinin adım adım uygulanması, test edilmesi ve doğrulanması için hazırlanmış teknik görevleri içerir.

---

## 🏗️ Faz 1: Backend API ve Sorgu Katmanının Zenginleştirilmesi (Backend Enrichment)

- [x] **1.1 SQL Sorgularına Favori Kontrolünün Entegre Edilmesi (`user_favorites` JOIN / EXISTS)**
  - [x] `backend/app/use_cases/listings/queries/search_listings_query.py`: `SearchListingsQuery` sınıfına `current_user_id` parametresi kullanılarak `user_favorites` tablosundan favori durumunu çeken alt sorgu (subquery / exists) veya LEFT JOIN eklenmesi.
  - [x] `backend/app/use_cases/listings/queries/get_my_listings.py` ve `get_listing.py`: Sorguların favori durumunu da kapsayacak şekilde zenginleştirilmesi.
- [x] **1.2 API Yanıt Şemalarının (Response Schema) Atomik Hale Getirilmesi**
  - [x] `backend/app/use_cases/listings/queries/listing_utils.py`: `_row_dict` ve `_parse_image_urls` yanındaki veri eşleme katmanına `"is_favorited": bool` alanının eklenmesi.
  - [x] Ana feed kartlarının uyumluluğu için `"is_liked"` alanının `(is_liked OR is_favorited)` mantığıyla (atomik / hibrit) hesaplanıp döndürülmesinin sağlanması.
- [x] **1.3 Servis Katmanında Çift Yönlü Atomik Senkronizasyon**
  - [x] `backend/app/services/like_service.py` ve `favorite_service.py`: Bir kullanıcı ilana beğeni (`/like`) veya favori (`/favorites`) gönderdiğinde/sildiğinde, veritabanı transaction bütünlüğü içinde her iki durumun birbiriyle tutarlı kalmasını sağlayan kontrol mantığının eklenmesi.

---

## 📱 Faz 2: Mobil Servis ve Önbellek Katmanı Senkronizasyonu (Mobile Service & Central Cache Sync)

- [x] **2.1 Merkezi Reaktif Provider Altyapısının Kurulması (Riverpod Integration)**
  - [x] `mobile/lib/services/listing_service.dart`: Statik `_likeCache` haritası yerine veya onunla entegre çalışan bir Riverpod `StateNotifierProvider` / `StateProvider` (örn: `listingInteractionCacheProvider`) kurgulanması.
  - [x] Cache okuma (`getCachedLike`) ve cache yazma (`setLikeCache`) metotlarının bu reaktif state akışını tetikleyecek şekilde güncellenmesi.
- [x] **2.2 Evrensel Etkileşim Metodunun (`toggleFavoriteAndLike`) Oluşturulması**
  - [x] `ListingService` içinde, mobil uygulamanın farklı yerlerindeki dağınık kalp butonlarını tek bir merkezde toplayacak `toggleFavoriteAndLike(int listingId, bool currentLiked)` metodunun yazılması.
  - [x] Bu metodun **Optimistic UI (İyimser Arayüz)** prensibiyle ağ isteği bitmeden önce cache'i hemen güncelleyerek anlık arayüz tepkisi vermesinin sağlanması.

---

## 🎨 Faz 3: UI Bileşenleri ve Ekranların Reaktif Bağlantısı (Reactive UI Integration)

- [x] **3.1 İlanlar Feed Ekranının (`home_screen.dart`) Reaktif Yapılandırılması**
  - [x] `_GridItemState` (ilan kartı bileşeni): Statik `_isLiked` değişkeninin kaldırılarak veya takviye edilerek `ref.watch(listingInteractionCacheProvider(widget.listing['id']))` ile merkezi reaktif cache'e bağlanması (`Observer Pattern`).
  - [x] `_toggleLike` metodundaki çift HTTP çağrısı (`ListingService.toggleLike` + `http.post(favorites)`) yerine yeni evrensel servisin çağrılması.
- [x] **3.2 İlan Detay Ekranının (`listing_detail_screen.dart`) Senkronizasyonu**
  - [x] `_toggleFavorite` metodunun revize edilmesi: Lokal `_isFavorited` ve `_isLiked` state değişiminin yanında zorunlu olarak merkezi reaktif cache'in güncellenmesi (`ListingService.setLikeCache(id, newStatus)`).
  - [x] Geri tuşuna basılıp İlanlar sayfasına dönüldüğünde kartların anında yeni durumu sergilemesinin garantiye alınması.
- [x] **3.3 Favorilerim Ekranından (`profile_screen.dart`) Silme İşleminde Cache Bağlantısı**
  - [x] `_FavoritesScreen` içindeki `_removeFavorite` metodunun incelenmesi ve silinen ilanın cache durumunun kesin olarak `false` (`ListingService.setLikeCache(id, false)`) yapılmasının sağlanması.

---

## 🧪 Faz 4: Uçtan Uca Doğrulama, Regresyon Testleri ve Telemetri (End-to-End Verification)

- [x] **4.1 Senaryo 1: Feed'den Favorileme ve Kontrol**
  - [x] Ana sayfadaki "Son İlanlar" feed'inde bir ilanın kalbine tıklanması -> İlanın anında favorilere eklendiğinin ve veritabanına doğru yazıldığının doğrulanması.
- [x] **4.2 Senaryo 2: Detay Sayfasında Değişiklik ve Feed'e Dönüş (Ana Regresyon Testi)**
  - [x] Bir ilanın detay sayfasına girilip favoriye alınması (veya favoriden çıkarılması).
  - [x] Geri tuşuna basılıp (sayfa refresh edilmeden) İlanlar feed'indeki ilgili kartın kalp ikonunun **anında doğru duruma** (dolu veya boş) geldiğinin doğrulanması.
- [x] **4.3 Senaryo 3: Favorilerim Listesinden Silme ve Feed Kontrolü**
  - [x] Profil -> Favorilerim ekranından bir ilanın silinmesi.
  - [x] İlanlar sayfasına dönüldüğünde ilanın üzerindeki kalp ikonunun boş (`Icons.favorite_border`) olduğunun doğrulanması.
- [x] **4.4 Analitik ve Telemetri Doğrulaması**
  - [x] `AnalyticsService.logInteraction` çağrılarının (`listing_favorite`, `listing_like`, vb.) mükerrer (çift) kayıt oluşturmadan tekil, doğru parametrelerle ve doğru subcategory bilgisiyle ClickHouse / Sentry / Firebase tarafına iletildiğinin kontrol edilmesi.
