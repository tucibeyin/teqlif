# V1.5 — Kayıt Detayı Zenginleştirme

## Bağlam

`recording_detail_screen.dart` mevcut haliyle video oynatıcı ve temel yayın özetini sunmaktadır. V1.5 ile bu ekran, yayından toplanan tüm veriyi (müzayedeler, satışlar, hediyeler, chat, katılımcı aksiyonları) zengin ve analitik bir biçimde sunan 4 sekmeli bir rapor ekranına dönüştürülecektir.

Backend değişikliği yoktur. Tüm veri `GET /api/streams/{id}/recording-summary` endpoint'inden zaten gelmektedir. Değişiklikler tamamen Flutter katmanındadır.

---

## Mevcut Veri Kaynakları

`RecordingDetail` modeli aşağıdaki alanları taşır:

| Alan | Tip | İçerik |
|---|---|---|
| `stream.title` | `String` | Yayın başlığı |
| `stream.category` / `subcategory` | `String?` | Kategori |
| `stream.startedAt` / `endedAt` | `DateTime?` | Başlangıç/bitiş |
| `stream.peakViewerCount` | `int?` | En yüksek eş zamanlı izleyici |
| `stream.recordingStartedAt` | `DateTime?` | Kaydın başladığı an (offset hesabı için baz) |
| `metrics.totalRevenue` | `double` | Toplam gelir (müzayede + satış) |
| `metrics.totalBids` | `int` | Toplam teklif sayısı |
| `metrics.totalSales` | `int` | Toplam satılan ürün adedi |
| `auctions[].auctionId` | `int` | Müzayede kimliği |
| `auctions[].itemName` | `String` | Ürün adı |
| `auctions[].startPrice` / `finalPrice` | `double?` | Başlangıç / kapanış fiyatı |
| `auctions[].bidCount` | `int` | Teklif sayısı |
| `auctions[].sold` | `bool` | Satıldı mı |
| `auctions[].winner` | `RecordingParticipant?` | Kazanan: `userId`, `username`, `avatarUrl` |
| `auctions[].bids[]` | `List<RecordingBid>` | `userId`, `username`, `avatarUrl`, `amount`, `offsetSecs` |
| `directSales[].saleId` | `int` | Satış kimliği |
| `directSales[].title` | `String` | Ürün başlığı |
| `directSales[].price` | `double?` | Birim fiyat |
| `directSales[].totalStock` / `soldCount` | `int` | Stok / satılan |
| `directSales[].orders[]` | `List<RecordingOrder>` | `userId`, `username`, `avatarUrl`, `quantity`, `unitPrice`, `offsetSecs` |
| `gifts.totalTeqlik` | `int` | Toplam hediye teqlik miktarı |
| `gifts.totalHostShare` | `int` | Host payı |
| `gifts.senderCount` | `int` | Benzersiz gönderici sayısı |
| `gifts.events[]` | `List<RecordingGiftEvent>` | `userId`, `username`, `avatarUrl`, `giftName`, `costTeqlik`, `offsetSecs` |
| `chatMessages[]` | `List<RecordingChatMessage>` | `userId`, `username`, `avatarUrl`, `content`, `isHost`, `isMod`, `offsetSecs` |

ViewModel `_buildTimeline()` tüm bu event'leri `offsetSecs`'e göre sıralayıp `List<ReplayEvent>` döndürmektedir. Aktivite Zaman Çizelgesi bu listeden üretilir.

---

## Model Değişiklikleri

### `mobile/lib/models/recording.dart` — Yeni Tipler

Aşağıdaki sınıflar `recording.dart` dosyasına eklenir. Bunlar View-only değildir; ViewModel tarafından üretilip `RecordingDetailState` içinde taşınır.

```dart
class ParticipantBidAction {
  final String auctionName;
  final double amount;
  final double? offsetSecs;
  const ParticipantBidAction({
    required this.auctionName,
    required this.amount,
    this.offsetSecs,
  });
}

class ParticipantOrderAction {
  final String itemName;
  final int quantity;
  final double unitPrice;
  final double? offsetSecs;
  const ParticipantOrderAction({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.offsetSecs,
  });
}

class ParticipantGiftAction {
  final String giftName;
  final int costTeqlik;
  final double? offsetSecs;
  const ParticipantGiftAction({
    required this.giftName,
    required this.costTeqlik,
    this.offsetSecs,
  });
}

class ParticipantChatAction {
  final String content;
  final bool isHost;
  final bool isMod;
  final double? offsetSecs;
  const ParticipantChatAction({
    required this.content,
    required this.isHost,
    required this.isMod,
    this.offsetSecs,
  });
}

enum ParticipantActionType { bid, order, gift, chat }

class ParticipantAnyAction {
  final ParticipantActionType type;
  final double? offsetSecs;
  final String label;
  final String? valueText;
  const ParticipantAnyAction({
    required this.type,
    this.offsetSecs,
    required this.label,
    this.valueText,
  });
}

class RecordingParticipantActivity {
  final int userId;
  final String username;
  final String? avatarUrl;
  final List<ParticipantBidAction>   bids;
  final List<ParticipantOrderAction> orders;
  final List<ParticipantGiftAction>  gifts;
  final List<ParticipantChatAction>  chats;

  RecordingParticipantActivity({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.bids,
    required this.orders,
    required this.gifts,
    required this.chats,
  });

  double get bidTotal      => bids.fold(0.0, (s, b) => s + b.amount);
  double get orderTotal    => orders.fold(0.0, (s, o) => s + o.quantity * o.unitPrice);
  int    get giftTeqlik    => gifts.fold(0, (s, g) => s + g.costTeqlik);
  int    get chatCount     => chats.length;
  double get monetaryTotal => bidTotal + orderTotal;

  // Kronolojik aksiyon listesi — late final ile bir kez hesaplanır.
  // Dinamik getter olarak tanımlanmaz; her build() çağrısında yeniden
  // klonlama/sıralama yapılması jank'e yol açar.
  late final List<ParticipantAnyAction> timeline = _buildTimeline();

  List<ParticipantAnyAction> _buildTimeline() {
    final items = <ParticipantAnyAction>[
      for (final b in bids)
        ParticipantAnyAction(
          type: ParticipantActionType.bid,
          offsetSecs: b.offsetSecs,
          label: b.auctionName,
          valueText: '₺${b.amount.toStringAsFixed(0)}',
        ),
      for (final o in orders)
        ParticipantAnyAction(
          type: ParticipantActionType.order,
          offsetSecs: o.offsetSecs,
          label: o.itemName,
          valueText: '×${o.quantity} ₺${o.unitPrice.toStringAsFixed(0)}',
        ),
      for (final g in gifts)
        ParticipantAnyAction(
          type: ParticipantActionType.gift,
          offsetSecs: g.offsetSecs,
          label: g.giftName,
          valueText: '${g.costTeqlik}⚡',
        ),
      for (final c in chats)
        ParticipantAnyAction(
          type: ParticipantActionType.chat,
          offsetSecs: c.offsetSecs,
          label: c.content,
        ),
    ];
    items.sort((a, b) => (a.offsetSecs ?? 0).compareTo(b.offsetSecs ?? 0));
    return items;
  }
}
```

### `mobile/lib/screens/viewmodels/recording_detail_view_model.dart` — State Değişiklikleri

`RecordingDetailState`'e `participants` alanı eklenir:

```dart
class RecordingDetailState {
  final RecordingUrlData? urlData;
  final RecordingDetail? summary;
  final bool summaryLoading;
  final bool summaryFailed;
  final String? urlError;
  final List<ReplayEvent> timeline;
  final bool replayEnabled;
  final List<RecordingParticipantActivity> participants; // YENİ

  const RecordingDetailState({
    this.urlData,
    this.summary,
    this.summaryLoading = false,
    this.summaryFailed = false,
    this.urlError,
    this.timeline = const [],
    this.replayEnabled = false,
    this.participants = const [],                        // YENİ
  });

  RecordingDetailState copyWith({
    RecordingUrlData? urlData,
    RecordingDetail? summary,
    bool? summaryLoading,
    bool? summaryFailed,
    String? urlError,
    bool clearUrlError = false,
    List<ReplayEvent>? timeline,
    bool? replayEnabled,
    List<RecordingParticipantActivity>? participants,   // YENİ
  }) {
    return RecordingDetailState(
      urlData:         urlData         ?? this.urlData,
      summary:         summary         ?? this.summary,
      summaryLoading:  summaryLoading  ?? this.summaryLoading,
      summaryFailed:   summaryFailed   ?? this.summaryFailed,
      urlError:        clearUrlError ? null : (urlError ?? this.urlError),
      timeline:        timeline        ?? this.timeline,
      replayEnabled:   replayEnabled   ?? this.replayEnabled,
      participants:    participants    ?? this.participants, // YENİ
    );
  }
}
```

`fetchSummary()` Ok branch'ine `participants` hesabı eklenir:

```dart
case Ok(:final value):
  final loc = ref.read(localizationProvider);
  final timeline     = _buildTimeline(value, loc);
  final participants = _buildParticipants(value);      // YENİ
  final replayEnabled = value.stream.recordingStartedAt != null
      && timeline.isNotEmpty;
  state = AsyncValue.data(
    (state.valueOrNull ?? const RecordingDetailState()).copyWith(
      summary:        value,
      summaryLoading: false,
      summaryFailed:  false,
      timeline:       timeline,
      replayEnabled:  replayEnabled,
      participants:   participants,                     // YENİ
    ),
  );
```

`_buildParticipants()` metodu ViewModel içine eklenir:

```dart
List<RecordingParticipantActivity> _buildParticipants(RecordingDetail detail) {
  final map = <int, ({
    String username,
    String? avatarUrl,
    List<ParticipantBidAction>   bids,
    List<ParticipantOrderAction> orders,
    List<ParticipantGiftAction>  gifts,
    List<ParticipantChatAction>  chats,
  })>{};

  void ensureUser(int id, String username, String? avatarUrl) {
    map[id] ??= (
      username:  username,
      avatarUrl: avatarUrl,
      bids:      [],
      orders:    [],
      gifts:     [],
      chats:     [],
    );
  }

  for (final a in detail.auctions) {
    for (final b in a.bids) {
      ensureUser(b.userId, b.username, b.avatarUrl);
      map[b.userId]!.bids.add(ParticipantBidAction(
        auctionName: a.itemName,
        amount:      b.amount,
        offsetSecs:  b.offsetSecs,
      ));
    }
  }

  for (final ds in detail.directSales) {
    for (final o in ds.orders) {
      ensureUser(o.userId, o.username, o.avatarUrl);
      map[o.userId]!.orders.add(ParticipantOrderAction(
        itemName:  ds.title,
        quantity:  o.quantity,
        unitPrice: o.unitPrice,
        offsetSecs: o.offsetSecs,
      ));
    }
  }

  for (final e in detail.gifts.events) {
    ensureUser(e.userId, e.username, e.avatarUrl);
    map[e.userId]!.gifts.add(ParticipantGiftAction(
      giftName:   e.giftName,
      costTeqlik: e.costTeqlik,
      offsetSecs: e.offsetSecs,
    ));
  }

  for (final m in detail.chatMessages) {
    if (m.userId == null) continue;
    ensureUser(m.userId!, m.username, m.avatarUrl);
    map[m.userId!]!.chats.add(ParticipantChatAction(
      content:    m.content,
      isHost:     m.isHost,
      isMod:      m.isMod,
      offsetSecs: m.offsetSecs,
    ));
  }

  return map.entries.map((e) => RecordingParticipantActivity(
    userId:   e.key,
    username: e.value.username,
    avatarUrl: e.value.avatarUrl,
    bids:    e.value.bids,
    orders:  e.value.orders,
    gifts:   e.value.gifts,
    chats:   e.value.chats,
  )).toList()
    ..sort((a, b) => b.monetaryTotal.compareTo(a.monetaryTotal));
}
```

---

## Ekran Mimarisi

### Genel Yapı

Video oynatıcı ve stream meta bilgisi üstte sabit kalır. Altında dört ana sekme bulunur. Her sekme bağımsız scroll context'ine sahiptir.

```
AppBar — Kayıt Detayı
Video Player (sabit, 16:9)
  Replay Overlay (offsetSecs'e göre son 5 event — değişmez)
Stream Meta: başlık · 📅 tarih · ⏱ süre · kategori badge
─────────────────────────────────────────────────────────
[Özet] [Müzayedeler] [Satış & Hediye] [Katılımcılar]
─────────────────────────────────────────────────────────
Tab içeriği (SingleChildScrollView, bağımsız)
```

Dış `DefaultTabController(length: 4)` ana sekmeleri yönetir. Dış `TabBarView`'a `physics: const NeverScrollableScrollPhysics()` uygulanır; sekmeler arası geçiş yalnızca tab başlığına dokunmayla gerçekleşir. Bu, "Katılımcılar" sekmesindeki iç TabBarView'un yatay swipe'ıyla çakışmayı önler.

### Dosya Yapısı

```
mobile/lib/
  models/
    recording.dart                         (RecordingParticipantActivity ve alt tipleri eklenir)
  screens/
    recording_detail_screen.dart           (iskelet: AppBar, video, meta, dış TabBar)
    recording_detail/
      overview_tab.dart                    (Sekme 1 — Özet)
      auctions_tab.dart                    (Sekme 2 — Müzayedeler)
      sales_gifts_tab.dart                 (Sekme 3 — Satış & Hediye)
      participants_tab.dart                (Sekme 4 — Katılımcılar, iç TabBar container)
      participants/
        overall_sub_tab.dart               (İç sekme: Genel sıralama + podyum)
        bids_sub_tab.dart                  (İç sekme: Teklif sıralaması)
        shopping_sub_tab.dart              (İç sekme: Alışveriş sıralaması)
        gifts_sub_tab.dart                 (İç sekme: Hediye sıralaması)
        chat_sub_tab.dart                  (İç sekme: Chat sıralaması)
      widgets/
        metric_grid.dart                   (6 metrik tile, TweenAnimationBuilder)
        activity_timeline.dart             (CustomPainter — aktivite çizelgesi)
        price_curve_painter.dart           (CustomPainter — müzayede fiyat eğrisi)
        gift_bars_painter.dart             (CustomPainter — hediye dağılım barları)
        podium_widget.dart                 (AnimatedContainer podyum, dinamik guard)
        stacked_avatars.dart               (Stack+Positioned üst üste avatarlar)
        participant_card.dart              (Tüm iç sekmelerde kullanılan ortak kart)
  viewmodels/
    recording_detail_view_model.dart       (_buildParticipants eklenir, state güncellenir)
```

---

## Sekme 1 — Özet

### Metrik Grid

6 metrik, 2×3 grid. `TweenAnimationBuilder<double>` ile her sayı 0'dan hedef değere animasyonlu sayar. Animasyon süresi 800ms, `Curves.easeOut`.

| Hücre | Değer | Kaynak |
|---|---|---|
| Gelir | `₺{totalRevenue}` | `metrics.totalRevenue` |
| Teklif | `{totalBids}` | `metrics.totalBids` |
| Müzayede | `{auctions.length}` | `detail.auctions.length` |
| Hediye | `{totalTeqlik} ⚡` | `gifts.totalTeqlik` |
| Peak İzleyici | `{peakViewerCount}` | `stream.peakViewerCount` |
| Chat | `{chatMessages.length}` | `chatMessages.length` |

### Aktivite Zaman Çizelgesi

`CustomPainter` ile 64px sabit yüksekliğinde çizilir. Veri kaynağı: `state.timeline` (`List<ReplayEvent>`).

**X ekseni:** `0` saniyeden `videoDuration` saniyesine. `videoDuration` kaynağı önceliği:
1. `_vpCtrl.value.duration.inSeconds` — video oynatıcı başlatıldıktan sonra
2. `RecordingItem.durationSecs` — recording listesinden gelen süre
3. `stream.endedAt.difference(stream.startedAt).inSeconds` — fallback; yayın süresi; transcoding farkı nedeniyle video süresiyle örtüşmeyebilir

**Y ekseni:** Dilim başına düşen event yoğunluğu. Dilim büyüklüğü: 15 saniye.

**Renkler:**
- Teklif: `kPrimary`
- Alım: `Color(0xFF6366F1)`
- Hediye: `Color(0xFFF97316)`
- Chat: `Colors.white38`

Her dilimde event sayıları kategoriye göre yığılı (stacked) bar olarak gösterilir. `GestureDetector` ile dokunulan dilimde `Tooltip` açılır; format: `"3 teklif · 1 alım · 2 hediye"`.

### Öne Çıkanlar

Dört satır. Her satır: `CircleAvatar(radius: 16)` + `@username` + değer metni. Tıklanınca `PublicProfileScreen`.

| İkon | Başlık | Hesaplama |
|---|---|---|
| 🏆 | En Yüksek Teklif | `bids` tümü içinde max `amount`; o bid'in `userId` ve `username`'i |
| 💎 | En Büyük Hediyeci | `gifts.events` group by `userId`; toplam `costTeqlik` en yüksek kullanıcı |
| 🛍️ | En Aktif Alıcı | `orders` group by `userId`; toplam `quantity * unitPrice` en yüksek kullanıcı |
| 💬 | En Fazla Konuşan | `chatMessages` group by `userId`; mesaj sayısı en yüksek kullanıcı |

Hesaplama `_SummarySectionState.initState()` veya `didChangeDependencies()`'de bir kez yapılır; `late final` ile önbelleklenir.

---

## Sekme 2 — Müzayedeler

Her müzayede için bağımsız kart. Kartlar `auctions` listesinin sırasıyla gösterilir.

### Fiyat Eğrisi

`price_curve_painter.dart` içinde `CustomPainter`. X ekseni: teklif sıra numarası `0..bids.length-1`. Y ekseni: normalise edilmiş teklif tutarı (`min..max` aralığı canvas yüksekliğine sığdırılır). Çizgi rengi `kPrimary`, kalınlık 2px. Son nokta: dolu daire. Sol üst: `₺{startPrice}`, sağ üst: `₺{finalPrice}`. Sağ üst badge: `+%{artış}` (`finalPrice / startPrice * 100 - 100`).

**Sıfıra bölme koruması:**
- `bids.isEmpty` → painter hiç çizmez; kart içinde "Teklif yok" metni gösterilir.
- `bids.length == 1` → tek nokta canvas ortasında çizilir; polyline atlanır; yüzde badge gösterilmez.

### Teklif Veren Avatar Grubu (`stacked_avatars.dart`)

Benzersiz bidder'lar, en son teklif verenden geriye doğru. `Stack` + `Positioned` ile her avatar bir öncekinin üzerine 16px ötelenir. Maksimum 5 avatar. 5'ten fazlası için son yuvaya `+N` metni içeren dolu daire eklenir. Her avatar `GestureDetector` ile `PublicProfileScreen`'e yönlendirir.

### Kazanan Satırı

`Icon(Icons.emoji_events, color: kPrimary, size: 16)` + `CircleAvatar(radius: 14)` + `@{username}` + `₺{finalPrice}`. Tıklanınca `PublicProfileScreen`. Müzayede satılmadıysa (`sold == false`) gösterilmez.

### Teklif Listesi

`ExpansionTile`. Her satır ters kronolojik (en son teklif en üstte): `CircleAvatar(radius: 14)` + `@username` + sağda `₺{amount}` + `{mm:ss}` offset damgası. Tıklanınca profil.

Offset damgası formatı: `int secs = offsetSecs.floor(); '${(secs ~/ 60).toString().padLeft(2,'0')}:${(secs % 60).toString().padLeft(2,'0')}'`. `offsetSecs` null ise damga gösterilmez.

---

## Sekme 3 — Satış & Hediye

### Direkt Satışlar

Her `RecordingDirectSale` için kart:

- Başlık metni bold + `₺{price}` sağda
- `LinearProgressIndicator(value: soldCount / totalStock)`, renk `Color(0xFF6366F1)`, `borderRadius` 2px. `totalStock == 0` durumunda gösterilmez.
- Alt satır: `{soldCount}/{totalStock} adet · %{oran} · Gelir ₺{soldCount * price}`
- Alıcı avatar satırı: `stacked_avatars.dart` ile `orders` içindeki benzersiz kullanıcılar. Tıklanınca profil.

### Hediye Dağılımı

Üst özet satırı: `{totalTeqlik} ⚡ toplam · {events.length} hediye · {senderCount} gönderici`

`gifts.events` group by `giftName` → her hediye türü için bar satırı:
- Emoji + isim metni
- `gift_bars_painter.dart` ile oransal yatay bar. En yüksek adet = %100 genişlik. Bar rengi `Color(0xFFF97316)`.
- Sağda `{count}× · %{oran}`

Gönderici sıralaması (en altta): group by `userId`, `costTeqlik` toplamı azalan. Her satır: `CircleAvatar(radius: 14)` + `@username` + `{toplam}⚡`. Tıklanınca profil.

---

## Sekme 4 — Katılımcılar

### İç Tab Yapısı

`DefaultTabController(length: 5)`, dış TabController'dan ayrı scope'ta. İç `TabBarView`'a `physics: const AlwaysScrollableScrollPhysics()` uygulanır; kullanıcı 5 alt sekme arasında yatay swipe ile geçer. Dış TabBarView'un `NeverScrollableScrollPhysics`'i bu swipe'ı yutmaz; Flutter jest çözümlemesinde en içteki `TabBarView` öncelik alır.

```
[Genel] [Teklif] [Alışveriş] [Hediye] [Chat]
```

### Podyum Widget (`podium_widget.dart`)

`AnimatedContainer` ile yükseklik animasyonu. `AnimationController(duration: 600ms)`, `Curves.easeOutBack`. #1 en yüksek kürsü (altın), #2 orta (gümüş), #3 en alçak (bronz). Her kürsüde: `CircleAvatar(radius: 28)`, `@username`, toplam parasal değer.

Dinamik guard — katılımcı sayısına göre:

| Katılımcı sayısı | Podyum davranışı |
|---|---|
| 0 | Podyum widget'ı render edilmez; `loc.t('recordingNoBuyers')` metni gösterilir |
| 1 | Tek kürsü, ortada hizalanmış, altın |
| 2 | İki kürsü: #1 sol, #2 sağ; bronz kürsü yoktur |
| 3+ | Üç kürsü standart düzen: #2 sol-orta, #1 merkez, #3 sağ-orta |

### Katılımcı Kartı (`participant_card.dart`)

Tüm 5 iç sekmede kullanılan ortak widget. Constructor parametreleri: `RecordingParticipantActivity participant`, `int rank`, `TranslationPack loc`.

Kart yapısı:

```
#rank  [CircleAvatar r:24]  @username        [expand ikon]
       ₺X teklif · ₺Y alım · Z⚡ · N msg
       (yalnızca 0'dan büyük olan alanlar gösterilir)
```

`ExpansionTile` açıldığında `participant.timeline` listesi kronolojik sırayla gösterilir. Her satır:

```
{mm:ss}  [ikon]  {label}  {valueText}
```

İkon ve renk eşleştirmesi:

| Tip | İkon | Renk |
|---|---|---|
| `bid` | `Icons.gavel` | `kPrimary` |
| `order` | `Icons.shopping_bag_outlined` | `Color(0xFF6366F1)` |
| `gift` | `Icons.card_giftcard_outlined` | `Color(0xFFF97316)` |
| `chat` | `Icons.chat_bubble_outline` | `AppColors.textSecondary` |

Avatar ve kullanıcı adı `GestureDetector` ile `PublicProfileScreen`'e yönlendirir.

### İç Sekme — Genel (`overall_sub_tab.dart`)

Sıralama: `monetaryTotal` azalan (`_buildParticipants` zaten bu sırayla döner).
Üstte podyum widget'ı. Altında #4'ten itibaren `participant_card.dart` listesi.

### İç Sekme — Teklif (`bids_sub_tab.dart`)

`state.participants` kopyası `bidTotal` azalana göre sıralanır. `bidTotal == 0` olan kullanıcılar listelenmez. Kart özet satırı: `{bids.length} müzayede · max ₺{bids.map(b=>b.amount).max}`.

### İç Sekme — Alışveriş (`shopping_sub_tab.dart`)

`orderTotal` azalana göre sıralama. `orders.isEmpty` olan kullanıcılar listelenmez. Kart özet satırı: `{orders.fold(0, quantity)} ürün · ₺{orderTotal}`.

### İç Sekme — Hediye (`gifts_sub_tab.dart`)

`giftTeqlik` azalana göre sıralama. `gifts.isEmpty` olan kullanıcılar listelenmez. Kart özet satırının yanında hediye emoji chip'leri: her benzersiz `giftName` için `{emoji}×{adet}`, boşlukla ayrılır.

### İç Sekme — Chat (`chat_sub_tab.dart`)

`chatCount` azalana göre sıralama. `chats.isEmpty` olan kullanıcılar listelenmez. Kart özet satırı: `{chatCount} mesaj`. Kart genişletilince chat aksiyonları gösterilir. Host mesajları sol border: 3px `kPrimary`. Moderatör mesajları sağda `Icon(Icons.shield, size: 12)`.

---

## Backend Uyumu

### Erişim Kontrolü

`GET /api/streams/{id}/recording-summary` endpoint'i `stream.host_id != current_user.id` kontrolü yapar; farklı bir kullanıcı isterse 403 döner. Bu ekran yalnızca yayıncının kendi kaydı için açılır; `my_recordings_screen.dart` üzerinden navigate edilmesi backend güvenlik modeliyle tam örtüşmektedir.

### `offset_secs` ve `recording_started_at`

Backend SQL:
```sql
EXTRACT(EPOCH FROM (created_at - CAST(:rec_start AS timestamptz))) AS offset_secs
```
`recording_started_at` veritabanında `NULL` ise `offset_secs` de `NULL` döner. `ParticipantBidAction`, `ParticipantOrderAction`, `ParticipantGiftAction`, `ParticipantChatAction` modellerinde `offsetSecs` alanının `double?` (nullable) olarak tanımlanması bu durumu kapsar. UI'da `offsetSecs == null` olduğunda zaman damgası gösterilmez.

### Null `user_id` Chat Mesajları

`stream_chat_messages` tablosunda sistem/duyuru mesajları `user_id = NULL` olarak kaydedilebilir. `_buildParticipants()` içindeki `if (m.userId == null) continue;` satırı bu mesajları katılımcı haritasına dahil etmeden atlar; `null` key'in haritayı bozmasını önler.

### Avatar URL Çözümlemesi

`GetRecordingSummaryQuery._full_url()` tüm avatar alanlarını MinIO/Uploads host'u eklenmiş tam URL olarak döndürür (`https://uploads.teqlif.com/...`). Flutter tarafında ek prefix işlemi yapılmaz; URL doğrudan `CachedNetworkImage` ve `CachedNetworkImageProvider`'a verilir.

---

## Dağıtım

ARB dosyaları güncellendikten sonra ayrı bir `sync_main.py` çalıştırma adımı gerekmez. `teqlif.service` ve `teqlif-staging.service` systemd dosyalarında:

```ini
ExecStartPre=/var/www/teqlif.com/.venv/bin/python scripts/sync_main.py
```

`sudo teqlif-restart` çalıştırıldığında `sync_main.py` otomatik devreye girer; 18 yeni ARB anahtarı `translations` tablosuna upsert edilir ve Redis i18n önbelleği temizlenir. Sıfır manuel adım gerekir.

---

## ADR Uyumu

| ADR Maddesi | Kural | V1.5 Karşılığı |
|---|---|---|
| §1 OTA Localization | Çeviriler ARB single source of truth; UI `loc.t(...)` ile okur | 18 anahtar ARB dosyalarına eklenir; tüm UI metinleri `loc.t(...)` üzerinden |
| §4 Central Error Handling | Ham exception / SnackBar yasak; `handleError(e, loc)` veya `ErrorMapper` kullanılır | ViewModel'ın mevcut `handleError` ve `summaryFailed` state mekanizması korunur |
| §13 Development Workflow | Clean Architecture, monolit parçalama, SRP | 1.730 satırlık monolit 15+ bağımsız tek-sorumluluklu widget dosyasına bölünür |
| §19 Stream Recording | LiveKit gizli abone ile MP4 kayıt; `recording_started_at` offset bazı | Video süresi `_vpCtrl.value.duration` öncelikli; `recording_started_at` offset hesabıyla senkron |
| §23 Cache & Repository | `RecordingRepository` 10 dakika lifecycle cache; state ViewModel'da | Repository ve API katmanı değiştirilmez; cache bypass yalnızca `recoverUrl()` içinde |

---

## ARB Anahtarları

18 yeni anahtar beş dil dosyasına eklenir: `app_tr.arb`, `app_en.arb`, `app_ar.arb`, `app_ru.arb`, `app_de.arb`. Eksik dil dosyası çalışma zamanında fallback uyarısı üretir. Değişiklikler ARB'a yazıldıktan sonra `sync_main.py` çalıştırılarak Redis'e işlenir.

| Anahtar | Türkçe | İngilizce | Arapça | Rusça | Almanca |
|---|---|---|---|---|---|
| `recordingMetricBids` | Teklif | Bids | عروض | Ставки | Gebote |
| `recordingMetricGifts` | Hediye | Gifts | هدايا | Подарки | Geschenke |
| `recordingActivityTimeline` | Aktivite | Activity | النشاط | Активность | Aktivität |
| `recordingTopSupporterLabel` | En Büyük Destekçi | Top Supporter | أكبر داعم | Главный сторонник | Top-Unterstützer |
| `recordingAuctionPriceJourney` | Fiyat Yolculuğu | Price Journey | مسار السعر | Динамика цены | Preisverlauf |
| `recordingGiftDistribution` | Hediye Dağılımı | Gift Distribution | توزيع الهدايا | Распределение подарков | Geschenkverteilung |
| `recordingParticipantTabOverall` | Genel | Overall | عام | Общий | Gesamt |
| `recordingParticipantTabBids` | Teklif | Bids | عروض | Ставки | Gebote |
| `recordingParticipantTabShopping` | Alışveriş | Shopping | تسوق | Покупки | Einkäufe |
| `recordingParticipantTabGifts` | Hediye | Gifts | هدايا | Подарки | Geschenke |
| `recordingParticipantTabChat` | Chat | Chat | دردشة | Чат | Chat |
| `recordingChatMessageCount` | {count} mesaj | {count} messages | {count} رسائل | {count} сообщений | {count} Nachrichten |
| `recordingTopChatters` | En Aktif Kullanıcılar | Most Active Users | أكثر المستخدمين نشاطًا | Самые активные | Aktivste Nutzer |
| `recordingLastMessage` | Son mesaj | Last message | آخر رسالة | Последнее сообщение | Letzte Nachricht |
| `recordingPodiumTitle` | Podyum | Podium | المنصة | Пьедестал | Podium |
| `recordingActionAt` | @{time} | @{time} | @{time} | @{time} | @{time} |
| `recordingHighestBid` | En Yüksek Teklif | Highest Bid | أعلى عرض | Максимальная ставка | Höchstgebot |
| `recordingNoBuyers` | Henüz katılımcı yok | No participants yet | لا مشاركين بعد | Пока нет участников | Noch keine Teilnehmer |

---

## MVVM Uyumluluk

`_buildViewers()` mevcut haliyle `recording_detail_screen.dart:309`'da View katmanına aittir. V1.5'te bu fonksiyon kaldırılır; yerine `_buildParticipants()` ViewModel'a taşınır ve sonuç `RecordingDetailState.participants` üzerinden sunulur. View salt okuma yapar.

View içindeki sıralama: Her iç sekme kendi `StatefulWidget` state'inde lokal sıralama tercihini tutar. Sıralama, `state.participants` listesinin `List.of()` kopyası üzerinde yapılır; ViewModel state'i değiştirilmez.

- **Model** (`recording.dart`): `RecordingParticipantActivity` ve alt tipleri eklenir.
- **ViewModel** (`recording_detail_view_model.dart`): `RecordingDetailState.participants` eklenir; `_buildParticipants()` eklenir; `fetchSummary()` Ok branch güncellenir. `retrySummary()` değişmez.
- **View** (`recording_detail_screen.dart` + alt dosyalar): `state.participants` okunur. Aggregation yok; lokal sort var.
- **Repository** (`recording_repository.dart`): Değişmez.
- **Backend**: Değişmez.

---

## Flutter Teknik Özet

| Yapı | Kullanım yeri |
|---|---|
| `DefaultTabController(length: 4)` | Dış sekme yönetimi, `recording_detail_screen.dart` |
| `NeverScrollableScrollPhysics` | Dış `TabBarView` — iç swipe çakışmasını önler |
| `DefaultTabController(length: 5)` | İç sekme yönetimi, `participants_tab.dart` |
| `TweenAnimationBuilder<double>` | Metrik sayaç animasyonu, `metric_grid.dart` |
| `CustomPainter` | Aktivite çizelgesi, fiyat eğrisi, hediye barları |
| `Stack` + `Positioned` | Üst üste avatar grubu, `stacked_avatars.dart` |
| `AnimatedContainer` + `AnimationController` | Podyum yükseklik animasyonu, `podium_widget.dart` |
| `ExpansionTile` | Teklif listesi, katılımcı aksiyon listesi |
| `LinearProgressIndicator` | Satış doluluk barı |
| `GestureDetector` → `Navigator.push` | Her avatar ve kullanıcı adı → `PublicProfileScreen` |
| `late final` | `RecordingParticipantActivity.timeline` — tek seferlik sort |

---

## Bağımlılıklar

Yeni dış kütüphane eklenmez. Tüm çizimler `CustomPainter` ile yapılır. Mevcut bağımlılıklar kullanılır: `cached_network_image`, `flutter_riverpod`, `chewie`, `video_player`.

---

## UX / Formatlama Düzeltmeleri (commit `d2b17e5e`)

Commit `c1e66024` ile dağıtılan V1.5'e yapılan düzeltmeler.

### Yeni Dosya: `rd_formatters.dart`

`mobile/lib/screens/recording_detail/widgets/rd_formatters.dart`

```dart
String rdLocale(String lang) {
  const map = {'tr':'tr_TR','en':'en_US','ar':'ar_SA','ru':'ru_RU','de':'de_DE'};
  return map[lang] ?? 'tr_TR';
}

String rdPrice(num amount, String lang) =>
    '₺${TeqNumberFormatter.format(amount, locale: rdLocale(lang))}';

String rdTeqliq(num amount, String lang) =>
    '${TeqNumberFormatter.format(amount, locale: rdLocale(lang))} teqliq';
```

**Kural:** Tüm fiyatlar `rdPrice(amount, loc.lang)`, tüm teqliq değerleri `rdTeqliq(amount, loc.lang)` ile gösterilir. `toStringAsFixed()` kullanımı yasaktır. `TeqNumberFormatter.format()` binlik ayraç ve locale desteği sağlar.

### Teqliq Yazım Kuralı

- Doğru: `teqliq` (küçük harf)
- Yanlış: `Teqlik`, `TQL`, `Teqliq`, `teqlik`

Tüm ekranlarda, tüm dillerde küçük harf `teqliq` kullanılır.

### Scrollable Tab Bar

Her iki tab bar da (`recording_detail_screen.dart` dış TabBar, `participants_tab.dart` iç TabBar) `isScrollable: true, tabAlignment: TabAlignment.start` ile yapılandırılır. Bu, uzun sekme isimlerinin kesilmesini önler; kullanıcı yatayda kaydırarak tüm sekmelere erişir.

```dart
TabBar(
  isScrollable: true,
  tabAlignment: TabAlignment.start,
  ...
)
```

### Yanıp Sönen Ok Göstergesi

Görünür alanın dışında sekme bulunduğunda sağ kenarda `FadeTransition` + gradient + `Icons.chevron_right_rounded` göstergesi belirer. `AnimationController.repeat(reverse: true)` ile 700ms aralıklı yanıp söner. Son sekme seçildiğinde otomatik kaybolur.

```dart
AnimationController _tabHintPulse = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 700),
)..repeat(reverse: true);

bool get _hasMoreRight => controller.index < tabs.length - 1;
```

`_TabBarWithHint` widget'ı hem `recording_detail_screen.dart` hem `participants_tab.dart`'ta kullanılır.

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `widgets/rd_formatters.dart` | Yeni: rdLocale / rdPrice / rdTeqliq |
| `overview_tab.dart` | rdPrice + rdTeqliq, _TopSupporterCard'a lang parametresi |
| `auctions_tab.dart` | rdPrice (_PriceLabel, _BidRow), rd_formatters import |
| `sales_gifts_tab.dart` | rdPrice + rdTeqliq, GiftBarsChart'a lang, _SaleModal/_GiftEventRow/_OrderRow'a loc |
| `widgets/gift_bars_painter.dart` | rdTeqliq, GiftBarsChart/GiftBar'a lang parametresi |
| `widgets/participant_card.dart` | rdPrice + rdTeqliq, lang parametresi eklendi |
| `participants/overall_sub_tab.dart` | ParticipantCard'a lang: loc.lang geçirildi |
| `participants/bids_sub_tab.dart` | rdPrice, _BidChip'e lang parametresi |
| `participants/shopping_sub_tab.dart` | rdPrice |
| `participants/gifts_sub_tab.dart` | rdTeqliq |
| `recording_detail_screen.dart` | AnimationController + _TabBarWithHint |
| `participants_tab.dart` | StatefulWidget'a dönüştürüldü, AnimationController + hint |
