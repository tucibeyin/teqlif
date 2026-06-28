import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/api.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../core/app_exception.dart';
import '../../core/logger_service.dart';
import '../../services/storage_service.dart';
import '../../services/stream_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/live/gift_hud.dart';
import '../../widgets/live/hype_meter_widget.dart';
import '../../utils/error_helper.dart';
import '../../widgets/auction_panel.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/chat_panel.dart';
import '../../widgets/live/cohost_mod_sheet.dart';
import '../../widgets/live/floating_hearts.dart';
import '../../widgets/live/raid_ended_overlay.dart';
import '../../widgets/live/viewer_top_bar.dart';
import '../../providers/pip_provider.dart';
import '../../services/pip_service.dart';
import '../public_profile_screen.dart';
import '../listing_detail_screen.dart';
import '../../services/feed_telemetry_service.dart';
import '../../services/analytics_service.dart';

// ── Feed item tipleri ────────────────────────────────────────────────────────

sealed class _FeedItem {
  const _FeedItem();
}

// ── Parent prefetch cache entry ──────────────────────────────────────────────
// Parent _SwipeLiveScreenState tarafından 2 sayfa ilerisine önceden
// bağlanılır; child bunu bulunca sadece listener kurup audio'yu açar.
class _PrefetchEntry {
  final Room room;
  final JoinTokenOut token;
  final EventsListener<RoomEvent> listener;
  _PrefetchEntry({required this.room, required this.token, required this.listener});
  void dispose() {
    listener.dispose();
    room.disconnect();
  }
}

// ── Raid köprüsü ─────────────────────────────────────────────────────────────
// Eski SwipeLiveScreen dispose olmadan önce raid hedefinin prefetch bağlantısını
// burada saklar; yeni ekranın _activate() bunu bulunca anında kullanır.
class _RaidPrefetchBridge {
  static int? _streamId;
  static _PrefetchEntry? _entry;

  static void put(int streamId, _PrefetchEntry entry) {
    _entry?.dispose(); // önceki varsa temizle
    _streamId = streamId;
    _entry = entry;
  }

  static _PrefetchEntry? take(int streamId) {
    if (_streamId == streamId) {
      final e = _entry;
      _streamId = null;
      _entry = null;
      return e;
    }
    // Başka stream için saklanmış → artık geçersiz, temizle
    _entry?.dispose();
    _streamId = null;
    _entry = null;
    return null;
  }
}

class _LiveItem extends _FeedItem {
  final StreamOut stream;
  const _LiveItem(this.stream);
}

class _ListingItem extends _FeedItem {
  final Map<String, dynamic> listing;
  final int slotIndex;
  final String streamCategory;
  const _ListingItem(this.listing, {this.slotIndex = 0, this.streamCategory = ''});
}

// İlan havuzu henüz yüklenmedi: siyah placeholder (stream widget değil).
class _LoadingListingItem extends _FeedItem {
  const _LoadingListingItem();
}

// ── SwipeLiveScreen ──────────────────────────────────────────────────────────

class SwipeLiveScreen extends StatefulWidget {
  final List<StreamOut> streams;
  final int initialIndex;

  const SwipeLiveScreen({
    super.key,
    required this.streams,
    required this.initialIndex,
  });

  /// Tek bir yayına doğrudan streamId ile katılmak için kullanılır.
  /// SwipeLiveScreen iç yapısı lazy token çekeceğinden önceden joinStream
  /// çağırmaya gerek yoktur.
  factory SwipeLiveScreen.single({required int streamId}) {
    return SwipeLiveScreen(
      streams: [
        StreamOut(
          id: streamId,
          roomName: '',
          title: '',
          category: '',
          viewerCount: 0,
          host: StreamHost(id: 0, username: ''),
        ),
      ],
      initialIndex: 0,
    );
  }

  @override
  State<SwipeLiveScreen> createState() => _SwipeLiveScreenState();
}

class _SwipeLiveScreenState extends State<SwipeLiveScreen> {
  late final PageController _pageCtrl;
  int _currentPage = 0;

  // Sonsuz swipe: canlı yayınlar güncellenir, ilanlar büyüyen havuzdan beslenir
  late List<StreamOut> _liveItems;
  final List<Map<String, dynamic>> _listingPool = [];
  bool _fetchingListings = false;
  // Oturum içinde sona erdiği tespit edilen yayınların ID'leri — döngüden çıkarılır
  final Set<int> _endedStreamIds = {};
  // Poll'dan tespit edilen biten current stream — child sayfaya isEnded ile geçirilir,
  // raid overlay child tarafından gösterilir.
  int? _polledEndedStreamId;

  // Dinamik grup yapısı: her grup = 1 yayın + N ilan
  // _groupBoundaries[i] = (startPage, listingCount, pinnedStreamId)
  // pinnedStreamId: grup inşa edilirken hangi yayına atandığı kalıcı olarak kaydedilir.
  // Bu sayede yayın bittiğinde o grubun başka bir yayına kayması önlenir.
  final List<(int, int, int?)> _groupBoundaries = [];
  int _nextGroupStartPage = 0;
  int _currentListingsPerGroup = 2; // initState'den itibaren 2; _trackStreamDwell ile güncellenir

  // Davranış takibi: yayın izleme süresine göre ilan sayısı güncellenir
  final List<int> _recentDwells = []; // son 10 yayın dwell süresi (ms)
  int? _dwellStart; // mevcut yayın sayfasına girildiği an (ms epoch)

  // Kişiselleştirme — tercih edilen ilan kategorileri (backend'den gelir)
  List<String> _preferredListingCategories = [];
  // Backend'e gönderilmeyi bekleyen event batch
  final List<Map<String, dynamic>> _pendingEvents = [];
  // Oturum ID'si (backend'de kullanıcı seansını ayırt eder)
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  // Periyodik canlı yayın kontrol timer'ı
  Timer? _streamCheckTimer;

  // Listing-only modunda inşa edilen grup sayısı.
  // Bu indeksten küçük gruplar yayın geri gelse bile listing gösterir
  // → yeni yayınlar kullanıcının mevcut konumunu bozmadan ileride çıkar.
  int _listingOnlyGroupCount = 0;

  // ── Parent-level prefetch: child ±1 bağlanırken parent +2/+3'ü hazırlar ──
  final Map<int, _PrefetchEntry> _prefetchCache = {};
  // Aktif sayfanın PiP aksiyonu — iOS back gesture intercept için
  VoidCallback? _pipAction;
  final Set<int> _prefetchConnecting = {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    // Aktif PiP varsa bu yayın ekranı açılmadan önce kapat
    if (PipService.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ProviderScope.containerOf(context, listen: false)
            .read(pipProvider.notifier)
            .disablePip();
        PipService.hidePip();
      });
    }
    _liveItems = widget.streams;
    _currentPage = _pageForLiveIndex(widget.initialIndex);
    _pageCtrl = PageController(initialPage: _currentPage);
    _loadListingFeed();
    _dwellStart = DateTime.now().millisecondsSinceEpoch;
    // Bildirimden gelirken single mod: arka planda tam listeyi çek
    if (widget.streams.length == 1 && widget.streams[0].roomName.isEmpty) {
      _expandFromSingleMode(widget.streams[0].id);
    } else {
      _schedulePrefetch(_currentPage);
    }
    // Kişiselleştirilmiş sıralama + listings_per_group backend'den çek
    _fetchPersonalizedConfig();
    // Her 30 saniyede canlı yayın durumunu kontrol et (WS gecikmesine karşı)
    _streamCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refreshLiveStreams();
    });
  }

  Future<void> _fetchPersonalizedConfig() async {
    final config = await StreamService.getSwipeLiveConfig();
    if (!mounted || config == null) return;
    final isSingle = widget.streams.length == 1 && widget.streams[0].roomName.isEmpty;
    setState(() {
      if (!isSingle && config.streams.isNotEmpty) {
        _liveItems = config.streams;
        // _currentPage DEĞİŞTİRME — PageController ile senkron kalmalı.
        // Kullanıcı zaten sayfaları kaydırmaya başlamış olabilir;
        // _currentPage=0 yapmak aktif stream widget'ını isActive=false yaparak
        // 403 algılamasını bozuyor ve bağlantı döngüsüne neden oluyor.
        if (_currentPage == 0) {
          _groupBoundaries.clear();
          _nextGroupStartPage = 0;
        }
      }
      // Backend lpg'yi sadece local dwell verisi yoksa kullan.
      // _recentDwells doluysa kullanıcı zaten adapt edilmiş değere sahip;
      // backend override etmemeli.
      if (_recentDwells.isEmpty) {
        _currentListingsPerGroup = config.listingsPerGroup;
      }
      _preferredListingCategories = config.preferredListingCategories;
    });
    if (!isSingle) _schedulePrefetch(_currentPage);
  }

  @override
  void dispose() {
    for (final e in _prefetchCache.values) {
      e.dispose();
    }
    _prefetchCache.clear();
    _streamCheckTimer?.cancel();
    _pageCtrl.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _flushPendingEvents(); // oturum kapanırken bekleyen eventleri gönder
    super.dispose();
  }

  void _flushPendingEvents() {
    if (_pendingEvents.isEmpty) return;
    final toSend = List<Map<String, dynamic>>.from(_pendingEvents);
    _pendingEvents.clear();
    StreamService.sendSwipeLiveEvents(toSend);
  }

  // ── Grup yönetimi ────────────────────────────────────────────────────────────

  /// targetGroupIdx'e kadar (dahil) grup sınırlarını lazy olarak inşa eder.
  /// Her grup, inşa anındaki geçerli yayın listesinden bir yayın ID'si pin'ler.
  /// Bu pin sayesinde yayın bitince grup başka bir yayına kaymaz, listing'e döner.
  void _ensureGroupsBuilt(int targetGroupIdx) {
    while (_groupBoundaries.length <= targetGroupIdx) {
      final groupIdx = _groupBoundaries.length;
      // Grup inşa anında geçerli yayınları hesapla ve bu gruba bir yayın pin'le
      final validItems = _endedStreamIds.isEmpty
          ? _liveItems
          : _liveItems.where((s) => !_endedStreamIds.contains(s.id)).toList();
      int? pinnedStreamId;
      if (validItems.isNotEmpty) {
        final streamIdx = (groupIdx - _listingOnlyGroupCount).clamp(0, validItems.length - 1) % validItems.length;
        pinnedStreamId = validItems[streamIdx].id;
      }
      _groupBoundaries.add((_nextGroupStartPage, _currentListingsPerGroup, pinnedStreamId));
      _nextGroupStartPage += 1 + _currentListingsPerGroup;
    }
  }

  /// Son izleme sürelerine göre grup başına ilan sayısını hesaplar (0–3).
  /// İlk yayından itibaren adapte eder; daha fazla veriyle daha kararlı hale gelir.
  int _computeListingsPerGroup() {
    if (_recentDwells.isEmpty) return 2; // soğuk başlangıç
    final avgMs = _recentDwells.fold(0, (a, b) => a + b) ~/ _recentDwells.length;
    // Eşikler gerçek kullanım davranışına göre ayarlandı:
    // < 5s  → hızlı geziniyor, akışa dalmamış → max ilan göster
    // 5-12s → normal izleme → orta
    // 12-30s → yayınla meşgul → az ilan
    // > 30s → yayına odaklanmış → ilan yok
    if (avgMs < 5000) return 3;
    if (avgMs < 12000) return 2;
    if (avgMs < 30000) return 1;
    return 0;
  }

  /// Bir yayın sayfasından çıkılınca dwell süresi kaydedilir, N güncellenir.
  /// N değişirse öndeki (henüz görülmemiş) gruplar da yeniden hesaplanır.
  void _trackStreamDwell(int dwellMs) {
    _recentDwells.add(dwellMs);
    if (_recentDwells.length > 10) _recentDwells.removeAt(0);
    final newN = _computeListingsPerGroup();
    final avgMs = _recentDwells.fold(0, (a, b) => a + b) ~/ _recentDwells.length;
    debugPrint('[SwipeLive] dwell=${dwellMs}ms avg=${avgMs}ms lpg: $_currentListingsPerGroup → $newN');
    if (newN == _currentListingsPerGroup) return;
    _currentListingsPerGroup = newN;
    // Mevcut sayfa ötesindeki grupları yeniden inşa et
    final firstFutureGroup = _groupBoundaries.indexWhere(
      (g) => g.$1 > _currentPage,
    );
    if (firstFutureGroup > 0) {
      _groupBoundaries.removeRange(firstFutureGroup, _groupBoundaries.length);
      final last = _groupBoundaries.last;
      _nextGroupStartPage = last.$1 + 1 + last.$2;
    }
  }

  /// initialIndex numaralı canlı yayının hangi PageView sayfasında olduğunu hesaplar.
  int _pageForLiveIndex(int liveIdx) {
    if (liveIdx < 0) return 0;
    _ensureGroupsBuilt(liveIdx);
    return _groupBoundaries[liveIdx].$1;
  }

  /// Sayfa indeksine göre hangi feed öğesinin gösterileceğini hesaplar.
  /// Grup yapısı: her grup = 1 yayın + N ilan (N dinamik, _groupBoundaries'da kayıtlı).
  /// Her grubun pinnedStreamId'si inşa anında sabitleniyor — dinamik modülo kayması yok.
  _FeedItem _itemAt(int pageIndex) {
    // pageIndex'i içeren grubu bul (lazy build)
    int groupIdx = 0;
    while (true) {
      _ensureGroupsBuilt(groupIdx);
      final (startPage, listingCount, _) = _groupBoundaries[groupIdx];
      if (pageIndex < startPage + 1 + listingCount) break;
      groupIdx++;
    }
    final (groupStart, listingCount, pinnedStreamId) = _groupBoundaries[groupIdx];
    final posInGroup = pageIndex - groupStart;

    // Listing-only modunda inşa edilmiş gruplar dondurulur:
    // yeni yayın gelse bile bu gruplar listing göstermeye devam eder.
    final isListingOnlyGroup = _listingOnlyGroupCount > 0 && groupIdx < _listingOnlyGroupCount;

    // Bu grubun pin'lendiği yayını bul
    // Pin'lenen yayın bitmişse veya hiç pin yoksa → bu grup listing gösterir
    StreamOut? pinnedStream;
    if (!isListingOnlyGroup && pinnedStreamId != null) {
      try {
        pinnedStream = _liveItems.firstWhere(
          (s) => s.id == pinnedStreamId && !_endedStreamIds.contains(s.id),
        );
      } catch (_) {
        pinnedStream = null; // Bitti veya listede yok → listing'e düş
      }
    }

    // Hiç geçerli yayın pin'i yoksa listing göster
    if (pinnedStream == null) {
      if (_listingPool.isEmpty) {
        debugPrint('[SwipeLive] _itemAt($pageIndex) → loading (pinned stream ended or no listings)');
        return const _LoadingListingItem();
      }
      final listingIdx =
          (groupIdx * (_currentListingsPerGroup + 1) + posInGroup) % _listingPool.length;
      final item = _listingPool[listingIdx];
      debugPrint('[SwipeLive] _itemAt($pageIndex) → listing id=${item["id"]} (pin=$pinnedStreamId ended/missing)');
      return _ListingItem(item, slotIndex: pageIndex, streamCategory: '');
    }

    if (posInGroup == 0) return _LiveItem(pinnedStream);
    // İlan slotu ama havuz henüz boş → placeholder (stream widget değil)
    if (_listingPool.isEmpty) return const _LoadingListingItem();
    // İlan slotu: posInGroup 1..listingCount
    // Her grup ve her slot için farklı ilan seç
    final listingIdx = (groupIdx * 3 + posInGroup - 1) % _listingPool.length;
    return _ListingItem(
      _listingPool[listingIdx],
      slotIndex: pageIndex,
      streamCategory: pinnedStream.category,
    );
  }

  void _onPageChanged(int page) {
    // Önceki sayfadan çıkılırken dwell süresi kaydet (stream sayfasıysa)
    if (_dwellStart != null) {
      final prevItem = _itemAt(_currentPage);
      if (prevItem is _LiveItem) {
        final dwellMs = DateTime.now().millisecondsSinceEpoch - _dwellStart!;
        _trackStreamDwell(dwellMs);
        _recordStreamEvent(prevItem.stream, dwellMs);
      }
      _dwellStart = null;
    }

    setState(() => _currentPage = page);

    // Yeni sayfada stream varsa dwell ölçümü başlat
    if (_itemAt(page) is _LiveItem) {
      _dwellStart = DateTime.now().millisecondsSinceEpoch;
    }

    _evictStalePrefetches(page);
    _schedulePrefetch(page);
    // Her 15 sayfada bir yenile (~5 grup)
    if (page > 0 && page % 15 == 0) {
      _loadListingFeed();
      _refreshLiveStreams();
    }
    // Her 20 event'te batch gönder
    if (_pendingEvents.length >= 20) _flushPendingEvents();
  }

  void _recordStreamEvent(StreamOut stream, int dwellMs) {
    _pendingEvents.add({
      'stream_id': stream.id,
      'listing_id': 0,
      'event_type': dwellMs < 2000 ? 'skip' : 'dwell',
      'dwell_ms': dwellMs,
      'stream_category': stream.category,
      'listing_category': '',
      'listings_seen': _currentListingsPerGroup,
      'slot_index': _currentPage,
      'session_id': _sessionId,
    });
  }

  void _recordEngagementEvent(StreamOut stream, String eventType) {
    _pendingEvents.add({
      'stream_id': stream.id,
      'listing_id': 0,
      'event_type': eventType,
      'dwell_ms': 0,
      'stream_category': stream.category,
      'listing_category': '',
      'listings_seen': 0,
      'slot_index': _currentPage,
      'session_id': _sessionId,
    });
    if (_pendingEvents.length >= 20) _flushPendingEvents();
  }

  void _recordListingEvent(int listingId, String eventType, {
    int dwellMs = 0,
    String listingCategory = '',
    int slotIndex = 0,
  }) {
    // Mevcut aktif yayın kategorisi
    final streamCategory = _getCurrentStream()?.category ?? '';
    _pendingEvents.add({
      'stream_id': 0,
      'listing_id': listingId,
      'event_type': eventType,
      'dwell_ms': dwellMs,
      'stream_category': streamCategory,
      'listing_category': listingCategory,
      'listings_seen': 0,
      'slot_index': slotIndex,
      'session_id': _sessionId,
    });
  }

  // ── Parent prefetch yönetimi ─────────────────────────────────────────────

  /// ±2 ve ±3 konumundaki live yayınları önceden bağlar.
  /// ±1 ve mevcut sayfa çocuk widget'lar tarafından yönetilir — parent bunları
  /// atlamalıdır. Aksi hâlde az yayın olduğunda (ör. 2 yayın, listing yok)
  /// aynı LiveKit odasına eş zamanlı iki bağlantı açılarak ICE yarışı oluşur.
  void _schedulePrefetch(int page) {
    // Çocuk widget'ların sorumluluğundaki stream ID'leri (mevcut ±1)
    final childStreams = <int>{};
    for (final d in [-1, 0, 1]) {
      final p = page + d;
      if (p < 0) continue;
      try {
        final item = _itemAt(p);
        if (item is _LiveItem) childStreams.add(item.stream.id);
      } catch (_) {}
    }

    for (final delta in [2, 3, 4, -2, -3, -4]) {
      final target = page + delta;
      if (target < 0) continue;
      try {
        final item = _itemAt(target);
        if (item is _LiveItem && !childStreams.contains(item.stream.id)) {
          _startParentPrefetch(item.stream);
        }
      } catch (_) {}
    }
  }

  Future<void> _startParentPrefetch(StreamOut stream) async {
    final id = stream.id;
    if (_prefetchCache.containsKey(id) || _prefetchConnecting.contains(id)) return;
    _prefetchConnecting.add(id);
    try {
      final token = await StreamService.joinStream(id);
      if (!mounted) { _prefetchConnecting.remove(id); return; }
      final room = Room();
      final evListener = room.createListener();
      // Prefetch modda sadece video track'leri subscribe et
      evListener.on<TrackPublishedEvent>((e) {
        if (e.publication.kind == TrackType.VIDEO && !e.publication.subscribed) {
          e.publication.subscribe();
        }
      });
      await room.connect(
        token.livekitUrl,
        token.token,
        connectOptions: const ConnectOptions(autoSubscribe: false),
      );
      if (!mounted) {
        evListener.dispose();
        room.disconnect();
        _prefetchConnecting.remove(id);
        return;
      }
      // Mevcut katılımcıların video track'lerini hemen subscribe et
      for (final p in room.remoteParticipants.values) {
        for (final pub in p.videoTrackPublications) {
          if (!pub.subscribed) pub.subscribe();
        }
      }
      if (mounted) {
        _prefetchCache[id] = _PrefetchEntry(room: room, token: token, listener: evListener);
      } else {
        evListener.dispose();
        room.disconnect();
      }
    } catch (_) {
      // Prefetch başarısız — child kendi _prefetchConnect()'ini kullanır
    } finally {
      _prefetchConnecting.remove(id);
    }
  }

  /// Child, kendi initState/prefetchConnect'inde bunu çağırarak hazır odayı alır.
  _PrefetchEntry? takePrefetchEntry(int streamId) {
    return _prefetchCache.remove(streamId);
  }

  /// Artık görünmeyecek yayınlara ait hazır odaları temizle.
  void _evictStalePrefetches(int currentPage) {
    final keepIds = <int>{};
    for (int delta = -4; delta <= 5; delta++) {
      try {
        final item = _itemAt(currentPage + delta);
        if (item is _LiveItem) keepIds.add(item.stream.id);
      } catch (_) {}
    }
    final staleIds = _prefetchCache.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in staleIds) {
      _prefetchCache.remove(id)?.dispose();
    }
  }

  /// Child widget evict edilirken kendi Room'unu buraya depolar.
  /// Aynı stream'in bir sonraki page slot'u bunu takePrefetchEntry ile alır → yeniden bağlanmaz.
  bool _depositRoom(int streamId, _PrefetchEntry entry) {
    if (_prefetchCache.containsKey(streamId)) {
      entry.dispose(); // zaten var, yenisini reddet
      return false;
    }
    _prefetchCache[streamId] = entry;
    return true;
  }

  /// O an aktif olan sayfanın stream'ini döner (listing slotundaysa null).
  StreamOut? _getCurrentStream() {
    if (_liveItems.isEmpty) return null;
    final item = _itemAt(_currentPage);
    return item is _LiveItem ? item.stream : null;
  }

  /// Bir yayının sona erdiği bildirildiğinde _endedStreamIds'e eklenir.
  /// Group-pinning sayesinde overlay bozulmaz: mevcut sayfanın grubu pin'li yayını
  /// göstermeye devam eder. Ancak bir sonraki döngüde bu grup listing'e düşer.
  void _onStreamEnded(int streamId) {
    if (_endedStreamIds.contains(streamId)) return;
    if (_polledEndedStreamId == streamId) _polledEndedStreamId = null;
    _endedStreamIds.add(streamId);
    if (!mounted) return;

    final remaining = _liveItems.where((s) => !_endedStreamIds.contains(s.id)).toList();
    debugPrint('[SwipeLive] stream_ended id=$streamId | remaining=${remaining.length}');
    setState(() {});
  }

  /// API'den güncel yayın listesini çekip _liveItems'ı günceller.
  /// Sadece yeni yayın ekler; silme işlemi yalnızca güvenilir sinyallerden
  /// (403 hatası veya WS stream_ended eventi) tetiklenir.
  /// Polling tabanlı silme false-positive üretiyordu: liste geçici eksik
  /// döndüğünde aktif yayınlar kaybolup geri gelmiyordu.
  Future<void> _refreshLiveStreams() async {
    try {
      final fresh = await StreamService.getActiveStreams();
      if (!mounted) return;
      final freshIds = fresh.map((s) => s.id).toSet();
      bool needsPrefetch = false;
      setState(() {
        // Bu refresh öncesi geçerli yayın sayısı
        final validBefore = _liveItems.where((s) => !_endedStreamIds.contains(s.id)).toList();

        // Yeni yayınları ekle
        final existingIds = _liveItems.map((s) => s.id).toSet();
        for (final s in fresh) {
          if (!existingIds.contains(s.id)) _liveItems.add(s);
        }
        if (fresh.isNotEmpty) {
          // Aktif listede olmayan yayınlar gerçekten bitmiş
          final currentStreamId = _getCurrentStream()?.id;
          for (final s in _liveItems) {
            if (!freshIds.contains(s.id) && !_endedStreamIds.contains(s.id)) {
              if (s.id == currentStreamId) {
                // İzlenen yayın bitti: child'a isEnded sinyali gönder (raid overlay).
                // Group-pinning sayesinde _endedStreamIds'e hemen eklesek de
                // bu grubun pin'i değişmez — overlay görünmeye devam eder.
                debugPrint('[SwipeLive] refresh: stream ${s.id} bitti (izleniyor) → raid overlay tetikleniyor');
                _polledEndedStreamId = s.id;
                _endedStreamIds.add(s.id);
              } else {
                debugPrint('[SwipeLive] refresh: stream ${s.id} aktif listede yok → ended');
                _endedStreamIds.add(s.id);
              }
            }
          }
        } else if (_endedStreamIds.isNotEmpty) {
          // Boş liste + bazı yayınlar zaten bitmişse: tüm kalan yayınlar da bitmiş
          for (final s in _liveItems) {
            if (!_endedStreamIds.contains(s.id)) {
              debugPrint('[SwipeLive] refresh: stream ${s.id} → boş liste + önceki bitişler → ended');
              _endedStreamIds.add(s.id);
            }
          }
        }

        // Listing-only → yayın var geçişi: mevcut grupları dondur
        // Böylece yeni yayınlar kullanıcının bulunduğu konumu bozmaz,
        // sadece ilerleyen sayfalarda organik olarak çıkar.
        final validAfter = _liveItems.where((s) => !_endedStreamIds.contains(s.id)).toList();
        if (validBefore.isEmpty && validAfter.isNotEmpty) {
          _listingOnlyGroupCount = _groupBoundaries.length;
          needsPrefetch = true;
          debugPrint(
            '[SwipeLive] refresh: ${validAfter.length} yeni yayın geldi, '
            '$_listingOnlyGroupCount grup listing-only donduruldu, page=$_currentPage',
          );
        }
      });
      if (needsPrefetch && mounted) _schedulePrefetch(_currentPage);
    } catch (_) {}
  }

  /// Bildirimden gelinen tek-yayın modunu tam listeye yükseltir.
  /// Hedef yayın başa alınır, diğerleri arkasına eklenir.
  Future<void> _expandFromSingleMode(int targetId) async {
    try {
      final fresh = await StreamService.getActiveStreams();
      if (!mounted || fresh.isEmpty) return;
      // Hedef yayını bulun (API'de varsa gerçek verisini kullan, yoksa stub'ı koru)
      final target = fresh.firstWhere(
        (s) => s.id == targetId,
        orElse: () => _liveItems[0],
      );
      final others = fresh.where((s) => s.id != targetId).toList();
      final expanded = [target, ...others];
      setState(() => _liveItems = expanded);
      _loadListingFeed();
      _schedulePrefetch(_currentPage);
    } catch (_) {}
  }

  Future<void> _loadListingFeed() async {
    if (_fetchingListings) return;
    _fetchingListings = true;
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/swipe-feed?limit=10'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));
      debugPrint('[SwipeLive] listing feed HTTP ${resp.statusCode}');
      if (resp.statusCode != 200) return;
      final List<dynamic> raw = jsonDecode(resp.body) as List<dynamic>;
      debugPrint('[SwipeLive] listing feed ${raw.length} ilan, page=$_currentPage lpg=$_currentListingsPerGroup');
      if (raw.isEmpty || !mounted) return;
      setState(() {
        final newItems = raw.cast<Map<String, dynamic>>();
        // Tercih edilen kategoriler öne, diğerleri arkaya (kararlı sıralama)
        if (_preferredListingCategories.isNotEmpty) {
          newItems.sort((a, b) {
            final catA = a['category']?.toString() ?? '';
            final catB = b['category']?.toString() ?? '';
            final rankA = _preferredListingCategories.indexOf(catA);
            final rankB = _preferredListingCategories.indexOf(catB);
            return (rankA < 0 ? 999 : rankA).compareTo(rankB < 0 ? 999 : rankB);
          });
        }
        _listingPool.addAll(newItems);
        // _LoadingListingItem slotları otomatik olarak yeniden çizilir:
        // _itemAt artık _listingPool.isNotEmpty olduğundan _ListingItem döndürür.
      });
      if (mounted) _schedulePrefetch(_currentPage);
    } catch (e) {
      debugPrint('[SwipeLive] listing feed hata: $e');
    } finally {
      _fetchingListings = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) _pipAction?.call();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: PageView.builder(
        controller: _pageCtrl,
        scrollDirection: Axis.vertical,
        physics: const PageScrollPhysics(),
        onPageChanged: _onPageChanged,
        // itemCount: null → sonsuz scroll
        itemCount: null,
        itemBuilder: (_, i) {
          final item = _itemAt(i);
          return switch (item) {
            _LiveItem(:final stream) => _SwipeLivePage(
                key: ValueKey('live_${stream.id}_$i'),
                stream: stream,
                isActive: i == _currentPage,
                isPrefetch: (i - _currentPage).abs() == 1,
                isLast: false,
                swipeLiveMode: true,
                isEnded: _polledEndedStreamId == stream.id,
                onStreamEnded: () => _onStreamEnded(stream.id),
                takePrefetch: takePrefetchEntry,
                onRoomDeposit: _depositRoom,
                onPipActionChanged: (cb) { _pipAction = cb; },
                onEngagementEvent: (type) => _recordEngagementEvent(stream, type),
              ),
            _ListingItem(:final listing, :final slotIndex, :final streamCategory) =>
              _ListingVideoPage(
                key: ValueKey('listing_${listing['id']}_$i'),
                listing: listing,
                isActive: i == _currentPage,
                slotIndex: slotIndex,
                streamCategory: streamCategory,
              ),
            _LoadingListingItem() => ColoredBox(
                key: ValueKey('loading_$i'),
                color: Colors.black,
              ),
          };
        },
      ),
      ),
    );
  }
}

// ── Tek yayın sayfası ────────────────────────────────────────────────────────

class _SwipeLivePage extends ConsumerStatefulWidget {
  final StreamOut stream;
  final bool isActive;
  final bool isPrefetch;
  final bool isLast;
  final VoidCallback? onStreamEnded;
  final _PrefetchEntry? Function(int streamId)? takePrefetch;
  final void Function(VoidCallback?)? onPipActionChanged;
  // Evict edilirken Room'u parent cache'e devret → aynı stream bir sonraki grupta anında hazır
  final bool Function(int streamId, _PrefetchEntry entry)? onRoomDeposit;
  // Etkileşim eventi — parent'a ML sinyali gönderir
  final void Function(String eventType)? onEngagementEvent;
  // true = çok yayınlı SwipeLive modu; davranış farklılaşır
  final bool swipeLiveMode;
  // Parent'tan gelen "yayın bitti" sinyali (poll tespiti) — child raid overlay gösterir
  final bool isEnded;

  const _SwipeLivePage({
    super.key,
    required this.stream,
    required this.isActive,
    required this.isLast,
    this.isPrefetch = false,
    this.isEnded = false,
    this.onStreamEnded,
    this.takePrefetch,
    this.onPipActionChanged,
    this.onRoomDeposit,
    this.onEngagementEvent,
    this.swipeLiveMode = false,
  });

  @override
  ConsumerState<_SwipeLivePage> createState() => _SwipeLivePageState();
}

class _SwipeLivePageState extends ConsumerState<_SwipeLivePage>
    with AutomaticKeepAliveClientMixin {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  JoinTokenOut? _token;
  VideoTrack? _remoteVideoTrack;       // Ana ekran — host'un video track'i
  VideoTrack? _coHostVideoTrack;       // PiP — başka birinin co-host track'i
  LocalVideoTrack? _localVideoTrack;   // PiP — kendim co-host olduğumda kamera
  String? _hostParticipantSid;         // İlk video track'i kimin olduğunu takip eder
  bool _loading = false;
  bool _streamEnded = false;
  int _viewerCount = 0;
  bool _selfMuted = false;
  bool _kicked = false;
  bool _isCoHost = false;
  bool _isSelfCoHost = false;          // Ben sahneye çıktım → local kamera açık
  double? _pipTop;                     // Sürüklenebilir PiP konumu
  double? _pipLeft;
  final Set<String> _coHostMutedUsers = {};
  final _heartsKey = GlobalKey<FloatingHeartsState>();
  Timer? _likeThrottleTimer;
  bool _likeThrottlePending = false;
  // single() modunda token geldikten sonra doldurulur
  String? _resolvedTitle;
  String? _resolvedHostUsername;
  // Sahne daveti kontrol için kendi kullanıcı adım
  String? _myUsername;
  // leaveStream'in çift çağrılmasını önler
  bool _leftStream = false;
  // PiP moduna geçilirken dispose'un Room'u kesmesini önler
  bool _enteringPip = false;
  // _activate() / _deactivate() race condition koruması
  int _activationGen = 0;
  // Bağlantı devam ederken veya room mevcut iken widget'ı PageView evict etme
  bool _keepAlive = false;

  @override
  bool get wantKeepAlive => _keepAlive || _room != null;

  void _setKeepAlive(bool v) {
    _keepAlive = v;
    if (mounted) updateKeepAlive();
  }
  // Prefetch modunda sadece video subscribe edilir, ses kapalı
  bool _isPrefetchMode = false;
  // Kazanan konfetisi
  late ConfettiController _confettiController;
  // Hediye HUD overlay
  OverlayEntry? _giftHudEntry;
  Timer? _giftHudTimer;
  final _hypeScore = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    if (widget.isActive) {
      widget.onPipActionChanged?.call(_pipForBackGesture);
      _activate();
    } else if (widget.isPrefetch) {
      _prefetchConnect();
    }
  }

  @override
  void didUpdateWidget(_SwipeLivePage old) {
    super.didUpdateWidget(old);
    // Parent poll'dan gelen "yayın bitti" sinyali: raid overlay göster
    if (widget.isEnded && !old.isEnded && !_streamEnded) {
      setState(() { _remoteVideoTrack = null; _streamEnded = true; });
      widget.onEngagementEvent?.call('raid_view');
    }
    if (widget.isActive && !old.isActive) {
      widget.onPipActionChanged?.call(_pipForBackGesture);
      // Sayfa aktif oldu
      if (_room != null) {
        _promoteToActive();  // zaten pre-bağlı → sesi aç
      } else {
        _activate();
      }
    } else if (!widget.isActive && old.isActive) {
      widget.onPipActionChanged?.call(null);
      // Sayfa aktif değil oldu
      if (widget.isPrefetch) {
        _demoteToPrefetch();  // komşu kalıyor → sesi kapat, video bağlı
      } else {
        if (!_tryDepositRoom()) _deactivate();
      }
    } else if (widget.isPrefetch && !old.isPrefetch && !widget.isActive && _room == null) {
      // Prefetch'e girdi, henüz bağlı değil
      _prefetchConnect();
    } else if (!widget.isPrefetch && !widget.isActive && (old.isPrefetch || old.isActive) && _room != null) {
      // Artık ne active ne prefetch → room'u parent'a devretmeyi dene, yoksa kapat
      if (!_tryDepositRoom()) _deactivate();
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _giftHudTimer?.cancel();
    _giftHudEntry?.remove();
    _hypeScore.dispose();
    _likeThrottleTimer?.cancel();
    if (!_enteringPip) _deactivateSync();
    super.dispose();
  }

  void _showGiftHud(String sender, String giftName, int cost) {
    if (!mounted) return;
    _giftHudTimer?.cancel();
    _giftHudEntry?.remove();
    _giftHudEntry = null;
    final overlay = Overlay.of(context);
    _giftHudEntry = OverlayEntry(
      builder: (_) => GiftHud(sender: sender, giftName: giftName, cost: cost),
    );
    overlay.insert(_giftHudEntry!);
    _giftHudTimer = Timer(const Duration(seconds: 4), () {
      _giftHudEntry?.remove();
      _giftHudEntry = null;
    });
  }

  Future<void> _showGiftSheet() async {
    final hostUsername = _resolvedHostUsername ?? widget.stream.host.username;
    if (hostUsername.isEmpty) return;

    const gifts = [
      ('🔥 Ateş', 10),
      ('💎 Elmas', 50),
      ('👑 Kral Tacı', 100),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GiftSheet(
        streamId: widget.stream.id,
        receiverUsername: hostUsername,
        gifts: gifts,
      ),
    );
  }

  void _onAuctionWon() {
    _confettiController.play();
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), HapticFeedback.vibrate);
  }

  // ── Ön yükleme (prefetch) ─────────────────────────────────────────────────

  /// Parent tarafından 2 sayfa ilerisinde önceden bağlanılmış bir oda varsa
  /// onu devralır: listener kurulur, mevcut track'ler state'e yazılır.
  /// Yoksa normal _prefetchConnect akışı devam eder.
  Future<void> _setupFromPrefetchEntry(_PrefetchEntry entry, {bool activate = false}) async {
    if (!mounted) { entry.dispose(); return; }
    final myGen = ++_activationGen;
    final room = entry.room;
    final token = entry.token;

    _resolvedTitle ??= token.title;
    _resolvedHostUsername ??= token.hostUsername;

    // Parent'ın minimal listener'ını değiştir, tam listener kur
    entry.listener.dispose();
    _listener = room.createListener();

    _listener!.on<TrackPublishedEvent>((e) {
      final shouldSub = e.publication.kind == TrackType.VIDEO || !_isPrefetchMode;
      if (shouldSub && !e.publication.subscribed) e.publication.subscribe();
    });
    _listener!.on<TrackSubscribedEvent>((e) {
      if (!mounted || e.track is! VideoTrack) return;
      final vTrack = e.track as VideoTrack;
      final isHost = e.participant.identity == token.hostLivekitIdentity;
      if (isHost) {
        setState(() { _remoteVideoTrack = vTrack; _hostParticipantSid = e.participant.sid; });
      } else if (e.participant.sid != _hostParticipantSid) {
        setState(() => _coHostVideoTrack = vTrack);
      }
    });
    _listener!.on<TrackUnsubscribedEvent>((e) {
      if (!mounted) return;
      if (e.track == _remoteVideoTrack) setState(() => _remoteVideoTrack = null);
      else if (e.track == _coHostVideoTrack) setState(() => _coHostVideoTrack = null);
    });
    _listener!.on<RoomDisconnectedEvent>((e) {
      if (!mounted) return;
      if (e.reason == DisconnectReason.roomDeleted) {
        if (widget.swipeLiveMode && !widget.isActive) {
          // Arka planda biten yayın → sessizce listeden çıkar
          setState(() => _remoteVideoTrack = null);
          widget.onStreamEnded?.call();
        } else {
          // Aktif sayfa veya single mod → overlay göster
          setState(() { _remoteVideoTrack = null; _streamEnded = true; });
          widget.onEngagementEvent?.call('raid_view');
        }
      } else {
        setState(() => _remoteVideoTrack = null);
      }
    });

    if (!mounted || _activationGen != myGen) { room.disconnect(); return; }

    // Mevcut katılımcılardan track'leri topla; aktiveyse audio da subscribe et
    VideoTrack? hostVideo;
    VideoTrack? coHostVideo;
    String? hostSid;
    for (final p in room.remoteParticipants.values) {
      final isHost = p.identity == token.hostLivekitIdentity;
      if (isHost) hostSid = p.sid;
      for (final pub in p.videoTrackPublications) {
        if (!pub.subscribed) pub.subscribe();
        if (pub.track != null) {
          if (isHost) hostVideo = pub.track as VideoTrack;
          else coHostVideo = pub.track as VideoTrack;
        }
      }
      if (activate) {
        for (final pub in p.audioTrackPublications) {
          if (!pub.subscribed) await pub.subscribe();
        }
      }
    }

    if (!mounted || _activationGen != myGen) { room.disconnect(); return; }

    _isPrefetchMode = !activate;
    if (_myUsername == null) {
      final info = await StorageService.getUserInfo();
      _myUsername = info?['username'] as String?;
    }

    setState(() {
      _token = token;
      _room = room;
      _loading = false;
      _streamEnded = false;
      if (hostSid != null) _hostParticipantSid = hostSid;
      if (hostVideo != null) _remoteVideoTrack = hostVideo;
      if (coHostVideo != null) _coHostVideoTrack = coHostVideo;
    });

    if (activate) {
      _leftStream = false;
      if (mounted) AnalyticsService.logInteraction(
        itemId: widget.stream.id,
        itemType: 'stream',
        interactionType: 'swipe_impression',
      );
    }
  }

  /// Evict edilirken mevcut Room'u parent'ın prefetch cache'ine devret.
  /// Başarılı olursa _room/_token/_listener temizlenir (disconnect edilmez),
  /// _leftStream=true yapılarak dispose'da leaveStream çağrılması önlenir.
  bool _tryDepositRoom() {
    if (_room == null || _token == null || _listener == null) return false;
    final entry = _PrefetchEntry(room: _room!, token: _token!, listener: _listener!);
    // Önce temizle: kabul veya ret olsun, bu slot artık room sahibi değil
    _activationGen++;
    _room = null;
    _token = null;
    _listener = null;
    _leftStream = true; // leaveStream başka slot üstlendi
    final accepted = widget.onRoomDeposit?.call(widget.stream.id, entry);
    if (accepted == true) return true;
    // Ret: başka bir slot zaten cache'e yazmış — entry.dispose() _depositRoom'da çağrıldı
    return false;
  }

  /// Kullanıcı henüz bu sayfaya gelmeden arka planda LiveKit'e bağlanır.
  /// Ses kapalıdır; video track gelir ve renderer hazır olur.
  /// Sayfa aktif olduğunda _promoteToActive() ile ses de açılır → anında izleme.
  Future<void> _prefetchConnect() async {
    if (!mounted || _room != null) return;

    // Parent 2 sayfa ilerisini önceden bağlamışsa kullan — çok daha hızlı
    final cached = widget.takePrefetch?.call(widget.stream.id);
    if (cached != null) {
      await _setupFromPrefetchEntry(cached, activate: false);
      return;
    }

    final myGen = ++_activationGen;

    try {
      if (_myUsername == null) {
        final info = await StorageService.getUserInfo();
        _myUsername = info?['username'] as String?;
      }
      if (!mounted || _activationGen != myGen) return;

      final token = await StreamService.joinStream(widget.stream.id);
      if (!mounted || _activationGen != myGen) return;

      if (_resolvedTitle == null) {
        _resolvedTitle = token.title;
        _resolvedHostUsername = token.hostUsername;
      }

      _isPrefetchMode = true;
      final room = Room();
      _listener = room.createListener();

      // Yeni track publish olduğunda: prefetch modda sadece video, active modda her şey
      _listener!.on<TrackPublishedEvent>((e) {
        if (e.publication.kind == TrackType.VIDEO || !_isPrefetchMode) {
          e.publication.subscribe();
        }
      });
      _listener!.on<TrackSubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          final vTrack = e.track as VideoTrack;
          final isHost = e.participant.identity == token.hostLivekitIdentity;
          if (isHost) {
            setState(() {
              _remoteVideoTrack = vTrack;
              _hostParticipantSid = e.participant.sid;
            });
          } else if (e.participant.sid != _hostParticipantSid) {
            setState(() => _coHostVideoTrack = vTrack);
          }
        }
      });
      _listener!.on<TrackUnsubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          if (e.track == _remoteVideoTrack) setState(() => _remoteVideoTrack = null);
          else if (e.track == _coHostVideoTrack) setState(() => _coHostVideoTrack = null);
        }
      });
      _listener!.on<RoomDisconnectedEvent>((e) {
        if (!mounted) return;
        if (e.reason == DisconnectReason.roomDeleted) {
          setState(() { _remoteVideoTrack = null; _streamEnded = true; });
        } else {
          setState(() => _remoteVideoTrack = null);
        }
      });

      await room.connect(
        token.livekitUrl,
        token.token,
        connectOptions: const ConnectOptions(autoSubscribe: false),
      );
      if (!mounted || _activationGen != myGen) {
        room.disconnect();
        return;
      }

      // Zaten stream'de olan katılımcıların video track'lerini subscribe et
      for (final p in room.remoteParticipants.values) {
        final isHost = p.identity == token.hostLivekitIdentity;
        if (isHost) _hostParticipantSid = p.sid;
        for (final pub in p.videoTrackPublications) {
          if (!pub.subscribed) pub.subscribe();
        }
      }
      if (!mounted || _activationGen != myGen) {
        room.disconnect();
        return;
      }

      setState(() { _token = token; _room = room; });

    } on AppException catch (e) {
      if (e.statusCode == 400 && mounted) _leave();
      else if (e.statusCode == 403 || e.statusCode == 404) widget.onStreamEnded?.call();
    } catch (_) {
      // Prefetch başarısız — kullanıcı sayfaya gelince _activate() yeniden dener
    }
  }

  /// Prefetch bağlantısı üzerinden tam izlemeye geç: audio subscribe et.
  Future<void> _promoteToActive() async {
    if (!mounted || _room == null) return;
    _leftStream = false;
    _isPrefetchMode = false;
    // Oda silindiyse (roomDeleted) _streamEnded sıfırlanmamalı
    if (mounted && !_streamEnded) setState(() => _streamEnded = false);

    final room = _room!;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        if (!pub.subscribed) await pub.subscribe();
      }
    }

    if (mounted) {
      AnalyticsService.logInteraction(
        itemId: widget.stream.id,
        itemType: 'stream',
        interactionType: 'swipe_impression',
      );
    }
  }

  /// Aktif sayfadan komşu sayfaya geç: audio unsubscribe et, video bağlı kalır.
  Future<void> _demoteToPrefetch() async {
    if (!mounted || _room == null) return;
    _isPrefetchMode = true;

    final room = _room!;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        if (pub.subscribed) await pub.unsubscribe();
      }
    }
  }

  Future<void> _activate([int attempt = 0]) async {
    if (!mounted) return;

    // Raid köprüsünden bağlantı aktar (eski ekrandan kurtarıldıysa) — debounce yok
    final bridged = _RaidPrefetchBridge.take(widget.stream.id);
    if (bridged != null) {
      await _setupFromPrefetchEntry(bridged, activate: true);
      return;
    }

    // Parent hızlı yoldan bağlamışsa doğrudan aktiflere geç — debounce yok
    final cached = widget.takePrefetch?.call(widget.stream.id);
    if (cached != null) {
      await _setupFromPrefetchEntry(cached, activate: true);
      return;
    }

    // Hızlı geçişlerde ICE başlatma: kullanıcı 300ms bu sayfada kalmazsa
    // bağlantıya gerek yok (activationGen ilerlediyse zaten iptal olur).
    // Widget evict edilse bile bağlantı tamamlanana dek keepAlive ile hayatta kalır.
    if (attempt == 0) { _keepAlive = true; updateKeepAlive(); }
    final myGen = ++_activationGen;
    if (attempt == 0) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || _activationGen != myGen) return;
    }
    _leftStream = false;
    setState(() {
      _loading = true;
      _remoteVideoTrack = null;
      _coHostVideoTrack = null;
      _streamEnded = false;
    });

    // Kendi kullanıcı adını yükle (sahne daveti kontrolü için)
    if (_myUsername == null) {
      final info = await StorageService.getUserInfo();
      _myUsername = info?['username'] as String?;
    }
    if (!mounted || _activationGen != myGen) return;

    try {
      final token = await StreamService.joinStream(widget.stream.id);
      if (!mounted || _activationGen != myGen) return;

      // single() modu: stub'daki boş title/username'i token'dan doldur
      if (_resolvedTitle == null) {
        setState(() {
          _resolvedTitle = token.title;
          _resolvedHostUsername = token.hostUsername;
        });
      }

      final room = Room();
      _listener = room.createListener();

      _listener!.on<TrackSubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          final vTrack = e.track as VideoTrack;
          final isHostTrack = e.participant.identity == token.hostLivekitIdentity;
          if (isHostTrack) {
            setState(() {
              _remoteVideoTrack = vTrack;
              _hostParticipantSid = e.participant.sid;
            });
          } else if (e.participant.sid != _hostParticipantSid) {
            // Farklı katılımcı = co-host → PiP'e
            setState(() => _coHostVideoTrack = vTrack);
          }
        }
      });
      _listener!.on<TrackUnsubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          if (e.track == _remoteVideoTrack) {
            setState(() => _remoteVideoTrack = null);
          } else if (e.track == _coHostVideoTrack) {
            setState(() => _coHostVideoTrack = null);
          }
        }
      });
      _listener!.on<RoomDisconnectedEvent>((e) {
        if (!mounted) return;
        if (e.reason == DisconnectReason.roomDeleted) {
          if (widget.swipeLiveMode && !widget.isActive) {
            setState(() => _remoteVideoTrack = null);
            widget.onStreamEnded?.call();
          } else {
            setState(() { _remoteVideoTrack = null; _streamEnded = true; });
            widget.onEngagementEvent?.call('raid_view');
            widget.onStreamEnded?.call();
          }
        } else {
          setState(() => _remoteVideoTrack = null);
        }
      });

      await room.connect(
        token.livekitUrl,
        token.token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );

      // _deactivate() bağlantı süresinde çağrıldıysa room'u temizle
      if (!mounted || _activationGen != myGen) {
        room.disconnect();
        return;
      }

      // Zaten yayında olan track'leri kontrol et
      for (final p in room.remoteParticipants.values) {
        final isHostParticipant = p.identity == token.hostLivekitIdentity;
        if (isHostParticipant) _hostParticipantSid = p.sid;
        for (final pub in p.videoTrackPublications) {
          if (pub.track != null) {
            final vTrack = pub.track as VideoTrack;
            if (isHostParticipant) {
              _remoteVideoTrack = vTrack;
            } else {
              _coHostVideoTrack = vTrack;
            }
          }
        }
      }

      if (mounted && _activationGen == myGen) {
        setState(() {
          _token = token;
          _room = room;
          _loading = false;
        });

        _setKeepAlive(false); // _room != null keepAlive'ı sürdürür

        // Bağlantı sırasında widget evict edildiyse: room'u parent cache'e bırak
        if (!widget.isActive && !widget.isPrefetch) {
          if (!_tryDepositRoom()) _deactivate();
          return;
        }

        AnalyticsService.logInteraction(
          itemId: widget.stream.id,
          itemType: 'stream',
          interactionType: 'swipe_impression',
        );
      }
    } on AppException catch (e) {
      _setKeepAlive(false);
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.statusCode == 400) {
        // Kendi yayınına viewer olarak katılma denemesi — sessizce geri dön
        _leave();
      } else if (e.statusCode == 403 || e.statusCode == 404) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.liveEnded), behavior: SnackBarBehavior.floating),
        );
        setState(() => _streamEnded = true);
        widget.onStreamEnded?.call();
      } else {
        showErrorSnackbar(context, e);
      }
    } catch (e, st) {
      _setKeepAlive(false);
      LoggerService.instance.captureException(e, stackTrace: st, tag: 'SwipeLivePage._activate');
      // Network/ICE geçici hatası: sayfa hâlâ aktifse otomatik yeniden dene (max 2 kez)
      // Spinner bekleme süresince görünür kalır; başarısız olursa loading temizlenir.
      if (mounted && widget.isActive && attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && widget.isActive) {
          _keepAlive = true; // yeniden dene — keepAlive tekrar ayarla
          _activate(attempt + 1);
        } else {
          if (mounted) setState(() => _loading = false);
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _handleMuted() {
    if (!mounted) return;
    setState(() => _selfMuted = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔇 Bu yayında susturuldunuz'),
        backgroundColor: Color(0xFFD97706),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _handleUnmuted() {
    if (!mounted) return;
    setState(() => _selfMuted = false);
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔊 ${l.modUnmutedMsg}'),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleKicked() {
    if (!mounted || _kicked) return;
    _kicked = true;
    _room?.disconnect();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚫 Bu yayından atıldınız'),
        backgroundColor: Color(0xFFEF4444),
        duration: Duration(seconds: 4),
      ),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  void _handleModPromotedSelf(String promotedBy) {
    if (!mounted || _isCoHost) return;
    setState(() => _isCoHost = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⭐ @$promotedBy sizi moderatör yaptı! Artık izleyicileri yönetebilirsiniz.'),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _handleModDemotedSelf(String demotedBy) {
    if (!mounted) return;
    setState(() => _isCoHost = false);
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.liveModDemotedSelf(demotedBy)),
        backgroundColor: const Color(0xFF475569),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showCoHostInviteDialog(String hostUsername) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Text('🎬', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'Sahneye Davet Edildiniz!',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          '@$hostUsername sizi sahneye davet etti.\nKameranız açılacak — kabul ediyor musunuz?',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Reddet', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kabul Et', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((accepted) {
      if (accepted == true) _acceptCoHostInvite();
    });
  }

  void _handleCoHostRemoved() {
    if (!mounted) return;
    // Kamerayı kapat, local track'i temizle
    _room?.localParticipant?.setCameraEnabled(false);
    _room?.localParticipant?.setMicrophoneEnabled(false);
    setState(() {
      _localVideoTrack = null;
      _isSelfCoHost = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📵 Sahneden kaldırıldınız'),
        backgroundColor: Color(0xFF475569),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _acceptCoHostInvite() async {
    // 1. Kamera ve mikrofon izni iste
    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (!mounted) return;
    if (camStatus.isDenied || micStatus.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sahneye çıkmak için kamera ve mikrofon izni gerekli'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Yeni can_publish=true token al
    late StreamTokenOut newToken;
    try {
      newToken = await StreamService.acceptCoHostInvite(widget.stream.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sahne bağlantısı kurulamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    // 3. Mevcut odadan çık (leaveStream çağırmıyoruz, yeniden join edeceğiz)
    _listener?.dispose();
    _listener = null;
    await _room?.disconnect();
    _room = null;
    _hostParticipantSid = null;
    _coHostVideoTrack = null;

    // 4. Yeni token ile odaya yayıncı olarak bağlan
    try {
      final room = Room();
      _listener = room.createListener();

      // Host'un track'ini ana ekrana bağla
      _listener!.on<TrackSubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          setState(() {
            _remoteVideoTrack = e.track as VideoTrack;
            _hostParticipantSid = e.participant.sid;
          });
        }
      });
      _listener!.on<TrackUnsubscribedEvent>((e) {
        if (e.track is VideoTrack && e.track == _remoteVideoTrack && mounted) {
          setState(() => _remoteVideoTrack = null);
        }
      });
      _listener!.on<LocalTrackPublishedEvent>((e) {
        if (e.publication.track is LocalVideoTrack && mounted) {
          setState(() => _localVideoTrack = e.publication.track as LocalVideoTrack);
        }
      });
      _listener!.on<RoomDisconnectedEvent>((e) {
        if (!mounted) return;
        if (e.reason == DisconnectReason.roomDeleted) {
          setState(() { _remoteVideoTrack = null; _localVideoTrack = null; _isSelfCoHost = false; _streamEnded = true; });
        } else {
          setState(() { _remoteVideoTrack = null; _localVideoTrack = null; _isSelfCoHost = false; });
        }
      });

      await room.connect(
        newToken.livekitUrl,
        newToken.token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );
      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);

      if (mounted) {
        setState(() {
          _room = room;
          _isSelfCoHost = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sahneye bağlanılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCoHostModSheet(String targetUsername) {
    final isMuted = _coHostMutedUsers.contains(targetUsername);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CoHostModSheet(
        streamId: widget.stream.id,
        username: targetUsername,
        isMuted: isMuted,
        onMuted:   () => setState(() => _coHostMutedUsers.add(targetUsername)),
        onUnmuted: () => setState(() => _coHostMutedUsers.remove(targetUsername)),
      ),
    );
  }

  Future<void> _deactivate() async {
    _setKeepAlive(false);
    _activationGen++;
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    _token = null;
    // Sesi/videoyu hemen kes — network çağrısını bekletme
    room?.disconnect();
    if (mounted) {
      setState(() {
        _remoteVideoTrack = null;
        _coHostVideoTrack = null;
        _localVideoTrack = null;
        _hostParticipantSid = null;
        _isSelfCoHost = false;
      });
    }
    // Backend'e ayrılma bildirimi fire-and-forget
    if (!_leftStream) {
      _leftStream = true;
      StreamService.leaveStream(widget.stream.id).catchError((e) {
        LoggerService.instance.warning('SwipeLivePage._deactivate', 'leaveStream başarısız: $e');
      });
    }
  }

  // dispose'da await kullanamayız, senkron temizlik
  void _deactivateSync() {
    _keepAlive = false; // mounted olmayabilir, updateKeepAlive çağırmıyoruz
    _activationGen++;
    _likeThrottleTimer?.cancel();
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    _token = null;
    _hostParticipantSid = null;
    room?.disconnect();
    if (!_leftStream) {
      _leftStream = true;
      try {
        StreamService.leaveStream(widget.stream.id);
      } catch (e) {
        LoggerService.instance.warning('SwipeLivePage._deactivateSync', 'leaveStream başarısız: $e');
      }
    }
  }

  void _onHeartTap() {
    HapticFeedback.lightImpact();
    _heartsKey.currentState?.addHeart(isLocal: true);
    if (_likeThrottleTimer?.isActive ?? false) {
      _likeThrottlePending = true;
    } else {
      _fireLikeRequest();
      _likeThrottleTimer = Timer(const Duration(milliseconds: 1500), () {
        if (_likeThrottlePending) {
          _likeThrottlePending = false;
          _fireLikeRequest();
        }
      });
    }
  }

  void _fireLikeRequest() {
    StreamService.likeStream(widget.stream.id).catchError((_) {});
    widget.onEngagementEvent?.call('stream_heart');
  }

  Future<void> _leave({bool fromOverlay = false}) async {
    if (widget.swipeLiveMode && fromOverlay) {
      // SwipeLive'da raid overlay'i kapattı — uygulamadan çıkma, yayını listeden çıkar
      widget.onEngagementEvent?.call('raid_close');
      widget.onStreamEnded?.call();
      await _deactivate();
      return;
    }
    widget.onStreamEnded?.call();
    await _deactivate();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  // iOS back gesture veya ← button'dan PiP kurulumu (senkron)
  void _pipForBackGesture() {
    if (_enteringPip || _leftStream) return; // Zaten işleniyor
    final track = _remoteVideoTrack;
    final room = _room;
    if (track == null || room == null) return; // Video yok, PiP açılamaz

    _enteringPip = true;
    _leftStream = true;
    StreamService.pipEnter(widget.stream.id);

    ref.read(pipProvider.notifier).enablePip(
      streamId: widget.stream.id,
      roomName: _resolvedTitle ?? widget.stream.title,
      hostUsername: _resolvedHostUsername ?? widget.stream.host.username,
      room: room,
      track: track,
    );

    if (mounted) PipService.showPip(context);
  }

  // ← butonu için: PiP kur + geri git
  Future<void> _enterPip() async {
    final track = _remoteVideoTrack;
    final room = _room;
    if (track == null || room == null) {
      await _leave();
      return;
    }
    _pipForBackGesture();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _handleRaid(int targetStreamId) async {
    widget.onEngagementEvent?.call('raid_chose');
    if (widget.swipeLiveMode) {
      // SwipeLive'da baskın seçildi — uygulamadan çıkma, biten yayını listeden çıkar
      // Hedef yayın zaten listede olabilir; kullanıcı swipe ederek ulaşabilir
      widget.onStreamEnded?.call();
      await _deactivate();
      return;
    }
    // Single mod: hedef yayına geç
    final bridgeEntry = widget.takePrefetch?.call(targetStreamId);
    if (bridgeEntry != null) {
      _RaidPrefetchBridge.put(targetStreamId, bridgeEntry);
    }
    widget.onStreamEnded?.call();
    await _deactivate();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SwipeLiveScreen.single(streamId: targetStreamId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin için gerekli
    final l = AppLocalizations.of(context)!;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final hasThumbnail =
        widget.stream.thumbnailUrl != null && widget.stream.thumbnailUrl!.isNotEmpty;

    return Stack(
      children: [
        // ── Arka plan: video veya thumbnail ──────────────────────────────
        if (_remoteVideoTrack != null)
          Positioned.fill(
            child: VideoTrackRenderer(
              _remoteVideoTrack!,
              fit: VideoViewFit.contain,
              mirrorMode: VideoViewMirrorMode.mirror,
            ),
          )
        else if (hasThumbnail)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: imgUrl(widget.stream.thumbnailUrl),
              fit: BoxFit.cover,
              placeholder: (_, __) => _darkBg(),
              errorWidget: (_, __, ___) => _darkBg(),
            ),
          )
        else
          Positioned.fill(child: _darkBg()),

        // ── Yükleniyor ───────────────────────────────────────────────────
        if (_loading)
          Positioned.fill(
            child: ColoredBox(
              color: hasThumbnail ? Colors.black38 : Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: kPrimary)),
            ),
          ),

        // ── Yayın sona erdi overlay ─────────────────────────────────────────
        if (_streamEnded)
          Positioned.fill(
            child: RaidEndedOverlay(
              streamId: widget.stream.id,
              hostUsername: _resolvedHostUsername ?? widget.stream.host.username,
              hostThumbnailUrl: widget.stream.thumbnailUrl,
              onClose: () => _leave(fromOverlay: true),
              onRaid: _handleRaid,
            ),
          ),

        // ── Üst gradient bar ─────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ViewerTopBar(
            topPad: topPad,
            viewerCount: _viewerCount,
            title: _resolvedTitle ?? widget.stream.title,
            hostUsername: _resolvedHostUsername ?? widget.stream.host.username,
            isCoHost: _isCoHost,
            streamEnded: _streamEnded,
            onLeave: _leave,
            onEnterPip: _streamEnded ? null : _enterPip,
            streamId: widget.stream.id,
            thumbnailUrl: widget.stream.thumbnailUrl,
          ),
        ),

        // ── Uçuşan kalpler ───────────────────────────────────────────────
        FloatingHearts(key: _heartsKey),

        // ── Hype Meter — sağ üst köşe, top bar altında ──────────────────
        Positioned(
          top: topPad + 64,
          right: 8,
          child: HypeMeterWidget(hypeScore: _hypeScore),
        ),

        // ── Co-Host PiP kutusu — sağ üst ────────────────────────────────
        // Öncelik: kendin co-host → local kamera. Değilse diğerinin track'i.
        if (_isSelfCoHost && _localVideoTrack != null)
          Positioned(
            top: _pipTop ?? (topPad + 70),
            left: _pipLeft ?? (MediaQuery.of(context).size.width - 110 - 16),
            child: GestureDetector(
              onPanUpdate: (d) {
                final s = MediaQuery.of(context).size;
                setState(() {
                  _pipTop  = ((_pipTop  ?? (topPad + 70)) + d.delta.dy).clamp(0.0, s.height - 160);
                  _pipLeft = ((_pipLeft ?? (s.width - 110 - 16)) + d.delta.dx).clamp(0.0, s.width - 110);
                });
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 110,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      VideoTrackRenderer(
                        _localVideoTrack!,
                        fit: VideoViewFit.contain,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () async {
                            final sid = _token?.streamId;
                            if (sid != null) {
                              try { await StreamService.leaveCoHost(sid); } catch (_) {}
                            }
                            _handleCoHostRemoved();
                          },
                          child: Container(
                            color: const Color(0xDDEF4444),
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            alignment: Alignment.center,
                            child: const Text(
                              '✕ Sahneden Çık',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (!_isSelfCoHost && _coHostVideoTrack != null)
          Positioned(
            top: _pipTop ?? (topPad + 70),
            left: _pipLeft ?? (MediaQuery.of(context).size.width - 110 - 16),
            child: GestureDetector(
              onPanUpdate: (d) {
                final s = MediaQuery.of(context).size;
                setState(() {
                  _pipTop  = ((_pipTop  ?? (topPad + 70)) + d.delta.dy).clamp(0.0, s.height - 160);
                  _pipLeft = ((_pipLeft ?? (s.width - 110 - 16)) + d.delta.dx).clamp(0.0, s.width - 110);
                });
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 110,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: VideoTrackRenderer(
                    _coHostVideoTrack!,
                    fit: VideoViewFit.contain,
                    mirrorMode: VideoViewMirrorMode.mirror,
                  ),
                ),
              ),
            ),
          ),

        // ── Swipe ipucu (son sayfa değilse) ─────────────────────────────
        if (!widget.isLast && !_streamEnded)
          Positioned(
            bottom: botPad + 104,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.keyboard_arrow_up_rounded,
                      color: Colors.white30, size: 24),
                  Text(l.liveNextStream,
                      style: const TextStyle(color: Colors.white30, fontSize: 11)),
                ],
              ),
            ),
          ),

        // ── Alt panel: sohbet + açık artırma ────────────────────────────
        if (widget.isActive && _token != null && !_streamEnded)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(bottom: botPad + 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                  stops: [0.0, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChatPanel(
                    streamId: widget.stream.id,
                    onStreamEnded: () {
                      if (widget.swipeLiveMode && !widget.isActive) {
                        widget.onStreamEnded?.call();
                      } else {
                        setState(() => _streamEnded = true);
                        widget.onEngagementEvent?.call('raid_view');
                      }
                    },
                    onViewerCountChanged: (n) =>
                        setState(() => _viewerCount = n),
                    onMuted: _handleMuted,
                    onUnmuted: _handleUnmuted,
                    onKicked: _handleKicked,
                    onModPromotedSelf: _handleModPromotedSelf,
                    onModDemotedSelf: _handleModDemotedSelf,
                    onModRestored: () {
                      if (mounted && !_isCoHost)
                        setState(() => _isCoHost = true);
                    },
                    onStreamLike: (_, __) =>
                        _heartsKey.currentState?.addHeart(isLocal: false),
                    onCoHostInvite: (hostUsername, targetUsername) {
                      if (!mounted || _isSelfCoHost) return;
                      if (targetUsername == _myUsername) {
                        _showCoHostInviteDialog(hostUsername);
                      }
                    },
                    onCoHostRemoved: (targetUsername) {
                      if (!mounted || !_isSelfCoHost) return;
                      if (targetUsername == _myUsername) {
                        _handleCoHostRemoved();
                      }
                    },
                    onUsernameTap: (username) {
                      if (_isCoHost) {
                        _showCoHostModSheet(username);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PublicProfileScreen(username: username),
                          ),
                        );
                      }
                    },
                    pinAtBottom: true,
                    onGift: _showGiftHud,
                    onHypeUpdate: (s) => _hypeScore.value = s,
                    trailingAction: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _showGiftSheet,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white30, width: 1.5),
                            ),
                            child: const Center(
                              child: Text('🎁', style: TextStyle(fontSize: 18)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _onHeartTap,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white30, width: 1.5),
                            ),
                            child: const Icon(
                              Icons.favorite,
                              color: Color(0xFFFF4081),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if ((_token?.category ?? widget.stream.category) != 'sohbet')
                    AuctionPanel(
                      streamId: widget.stream.id,
                      isHost: false,
                      isCoHost: _isCoHost,
                      enabled: !_selfMuted,
                      hostUserId: int.tryParse(_token?.hostLivekitIdentity ?? ''),
                      myUsername: _myUsername,
                      onWin: _onAuctionWon,
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        // ── Kazanan konfetisi — tüm ekranı kaplar ───────────────────────
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
            gravity: 0.2,
            colors: const [
              Color(0xFFFBBF24), // amber
              Color(0xFF06B6D4), // cyan (tema rengi)
              Color(0xFF22D3EE), // cyan-light
              Color(0xFFF97316), // orange
              Colors.white,
            ],
          ),
        ),
      ],
    );
  }

  Widget _darkBg() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Center(
          child: Icon(Icons.videocam_rounded, color: Colors.white10, size: 56),
        ),
      );
}

// ── Hediye Seçim Paneli ───────────────────────────────────────────────────────

class _GiftSheet extends StatefulWidget {
  final int streamId;
  final String receiverUsername;
  final List<(String, int)> gifts;

  const _GiftSheet({
    required this.streamId,
    required this.receiverUsername,
    required this.gifts,
  });

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  bool _sending = false;

  Future<void> _send(String giftName, int cost) async {
    if (_sending) return;
    setState(() => _sending = true);
    final result = await WalletService.sendGift(
      streamId: widget.streamId,
      receiverUsername: widget.receiverUsername,
      giftName: giftName,
      cost: cost,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (result['ok'] == true) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$giftName gönderildi! 🎉'),
          backgroundColor: const Color(0xFF6D28D9),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] as String? ?? 'Hata oluştu.'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, botPad + 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            '🎁 Hediye Gönder',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(color: Color(0xFF6D28D9)),
            )
          else
            Row(
              children: widget.gifts.map((g) {
                final (name, cost) = g;
                final emoji = name.split(' ').first;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => _send(name, cost),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 32)),
                            const SizedBox(height: 6),
                            Text(
                              name.contains(' ') ? name.substring(name.indexOf(' ') + 1) : name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$cost TUCi',
                              style: const TextStyle(
                                color: Color(0xFFA78BFA),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ── İlan Video Sayfası ───────────────────────────────────────────────────────

class _ListingVideoPage extends StatefulWidget {
  final Map<String, dynamic> listing;
  final bool isActive;
  final int slotIndex;
  final String streamCategory;

  const _ListingVideoPage({
    super.key,
    required this.listing,
    required this.isActive,
    this.slotIndex = 0,
    this.streamCategory = '',
  });

  @override
  State<_ListingVideoPage> createState() => _ListingVideoPageState();
}

class _ListingVideoPageState extends State<_ListingVideoPage> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;

  final Stopwatch _stopwatch = Stopwatch();
  bool _eventLogged = false;

  void _startWatch() {
    _stopwatch.reset();
    _stopwatch.start();
    _eventLogged = false;
  }

  void _stopAndLog() {
    if (!_stopwatch.isRunning || _eventLogged) return;
    _stopwatch.stop();
    _eventLogged = true;
    final ms = _stopwatch.elapsedMilliseconds;
    final lid = (widget.listing['id'] ?? '').toString();
    final hasVideo = (widget.listing['video_url'] as String?) != null &&
        (widget.listing['video_url'] as String).isNotEmpty;
    FeedTelemetryService.instance.logEvent(
      listingId: lid,
      eventType: ms < 2000 ? 'skip' : 'impression',
      dwellTimeMs: ms,
      contentType: hasVideo ? 'video' : 'photo',
      slotIndex: widget.slotIndex,
      streamCategory: widget.streamCategory,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _startWatch();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final videoUrl = widget.listing['video_url'] as String?;
    if (videoUrl == null || videoUrl.isEmpty) {
      // Video yok — fotoğraf direkt gösterilecek, spinner'a gerek yok
      if (mounted) setState(() => _initialized = true);
      return;
    }
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(imgUrl(videoUrl)));
    await _ctrl!.initialize();
    _ctrl!.setLooping(true);
    if (!mounted) return;
    setState(() => _initialized = true);
    if (widget.isActive) _ctrl!.play();
  }

  @override
  void didUpdateWidget(_ListingVideoPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl?.play();
      _startWatch();
    } else if (!widget.isActive && old.isActive) {
      _ctrl?.pause();
      _stopAndLog();
    }
  }

  @override
  void dispose() {
    _stopAndLog();
    _ctrl?.dispose();
    super.dispose();
  }

  void _goToListing() {
    // Detay ekranı açılmadan önce videoyu durdur
    _ctrl?.pause();
    final hasVideo = (widget.listing['video_url'] as String?) != null &&
        (widget.listing['video_url'] as String).isNotEmpty;
    FeedTelemetryService.instance.logEvent(
      listingId: (widget.listing['id'] ?? '').toString(),
      eventType: 'click',
      dwellTimeMs: _stopwatch.elapsedMilliseconds,
      contentType: hasVideo ? 'video' : 'photo',
      slotIndex: widget.slotIndex,
      streamCategory: widget.streamCategory,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listing: widget.listing),
      ),
    ).then((_) {
      // Kullanıcı geri döndüğünde ve hâlâ aktif sayfadaysak devam et
      if (mounted && widget.isActive) _ctrl?.play();
    });
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '—';
    final n = double.tryParse(price.toString());
    if (n == null) return price.toString();
    return n == n.truncateToDouble()
        ? n.truncate().toString()
        : n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final title = listing['title']?.toString() ?? '';
    final price = listing['price'];
    final category = listing['category']?.toString() ?? '';
    final location = listing['location']?.toString() ?? '';
    final username = (listing['user'] as Map<String, dynamic>?)?['username']?.toString() ?? '';
    final thumbUrl = listing['thumbnail_url']?.toString() ??
        listing['image_url']?.toString() ?? '';
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onTap: _goToListing,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video veya thumbnail ──────────────────────────────────────────
          if (_initialized && _ctrl != null)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _ctrl!.value.size.width,
                height: _ctrl!.value.size.height,
                child: VideoPlayer(_ctrl!),
              ),
            )
          else if (thumbUrl.isNotEmpty)
            CachedNetworkImage(imageUrl: imgUrl(thumbUrl), fit: BoxFit.cover)
          else
            const ColoredBox(color: Colors.black),

          // ── Yüklenme göstergesi ───────────────────────────────────────────
          if (!_initialized)
            const Center(child: CircularProgressIndicator(color: kPrimary)),

          // ── İLAN rozeti (sol üst) ─────────────────────────────────────────
          Positioned(
            top: topPad + 12,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFB8860B),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'İLAN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                ),
              ),
            ),
          ),

          // ── Alt bilgi paneli ──────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 40, 16, botPad + 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Satıcı + kategori
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          color: Colors.white60, size: 14),
                      const SizedBox(width: 4),
                      Text('@$username',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12)),
                      const Spacer(),
                      if (category.isNotEmpty)
                        Text(category,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Başlık
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Fiyat + konum
                  Row(
                    children: [
                      Text(
                        '${_formatPrice(price)} TL',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.location_on_outlined,
                            color: Colors.white54, size: 13),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            location,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  // İlana Git butonu
                  GestureDetector(
                    onTap: _goToListing,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB8860B), Color(0xFFFFD700)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'İlana Git',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
