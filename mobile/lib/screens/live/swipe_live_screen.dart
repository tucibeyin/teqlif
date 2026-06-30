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
import '../profile_screen.dart';
import '../listing_detail_screen.dart';
import '../../services/feed_telemetry_service.dart';
import '../../services/analytics_service.dart';

import '../../services/feed_manager.dart';
import '../../services/listing_video_manager.dart';
import '../../services/stream_connection_manager.dart';
import '../../services/push_notification_service.dart';

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

  /// Tam veriyle doğrudan yayına katılmak için kullanılır.
  factory SwipeLiveScreen.fromStream(StreamOut stream) {
    return SwipeLiveScreen(
      streams: [stream],
      initialIndex: 0,
    );
  }

  @override
  State<SwipeLiveScreen> createState() => _SwipeLiveScreenState();
}

class _SwipeLiveScreenState extends State<SwipeLiveScreen> {
  static int activeScreenCount = 0;
  bool _isCoHostLocked = false;

  late final PageController _pageCtrl;
  int _currentPage = 0;

  final SwipeFeedManager _feedManager = SwipeFeedManager();
  final StreamConnectionManager _connectionManager = StreamConnectionManager.instance;

  bool _fetchingListings = false;
  int? _polledEndedStreamId;

  // Davranış takibi: yayın izleme süresine göre ilan sayısı güncellenir
  final List<int> _recentDwells = []; // son 10 yayın dwell süresi (ms)
  int _currentListingsPerGroup = 2;
  int? _dwellStart;        // mevcut yayın sayfasına girildiği an (ms epoch)
  int? _listingPageStart;  // mevcut ilan sayfasına girildiği an (ms epoch)
  int _fastListingStreak = 0;
  static const int _listingFastThresholdMs = 1500;

  int _listingPage = 0;
  bool _hasMoreListings = true;
  
  // Kişiselleştirme — tercih edilen ilan kategorileri (backend'den gelir)
  List<String> _preferredListingCategories = [];
  // Backend'e gönderilmeyi bekleyen event batch
  final List<Map<String, dynamic>> _pendingEvents = [];
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  Timer? _streamCheckTimer;
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  bool _isRefreshingLive = false;

  VoidCallback? _pipAction;

  @override
  void initState() {
    super.initState();
    activeScreenCount++;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    if (PipService.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ProviderScope.containerOf(context, listen: false)
            .read(pipProvider.notifier)
            .disablePip(disconnectRoom: false);
        PipService.hidePip();
      });
    }
    
    _feedManager.init(
      initialStreams: widget.streams, 
      initialIndex: widget.initialIndex,
    );
    _currentPage = _feedManager.getPageForLiveIndex(widget.initialIndex);
    _pageCtrl = PageController(initialPage: _currentPage);
    
    _loadListingFeed();
    _dwellStart = DateTime.now().millisecondsSinceEpoch;
    
    if (widget.streams.length == 1) {
      _expandFromSingleMode(widget.streams[0].id);
    }
    
    // Uygulama ilk açıldığında aktif ve prefetch yayınlarını anında bağla
    _updateViewportConnections();
    
    _fetchPersonalizedConfig();
    // Her 15 saniyede canlı yayın durumunu kontrol et (daha hızlı güncellemeler için)
    _streamCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_isRefreshingLive) _refreshLiveStreams();
    });

    _notifSub = PushNotificationService.notificationStream.stream.listen((data) {
      // Eğer foreground (boş map) veya stream_started bildirimi gelirse feed'i güncelle
      final type = data['type'] as String?;
      if ((data.isEmpty || type == 'stream_started') && mounted && !_isRefreshingLive) {
        _refreshLiveStreams();
      }
    });
  }

  Future<void> _fetchPersonalizedConfig() async {
    final config = await StreamService.getSwipeLiveConfig();
    if (!mounted || config == null) return;
    final isSingle = widget.streams.length == 1 && widget.streams[0].roomName.isEmpty;
    setState(() {
      int lpg = 2;
      if (_recentDwells.isEmpty) {
        lpg = config.listingsPerGroup;
      } else {
        final avgMs = _recentDwells.reduce((a, b) => a + b) / _recentDwells.length;
        if (avgMs > 15000) {
          lpg = 1;
        } else if (avgMs < 3000) {
          lpg = 3;
        } else {
          lpg = 2;
        }
      }
      
      _currentListingsPerGroup = lpg;
      if (!isSingle && config.streams.isNotEmpty) {
        _feedManager.updateConfig(
          streams: config.streams,
          listingsPerGroup: _currentListingsPerGroup,
          preferredCategories: config.preferredListingCategories,
          currentIndex: _currentPage,
        );
      }
      _preferredListingCategories = config.preferredListingCategories;
    });
  }

  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container ??= ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    activeScreenCount--;
    _notifSub?.cancel();
    _streamCheckTimer?.cancel();
    _pageCtrl.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _flushPendingEvents(); // oturum kapanırken bekleyen eventleri gönder
    
    // PiP aktifse, ilgili yayını korumak için exclude listesine al
    final pip = _container?.read(pipProvider);
    final pipStreamId = (pip?.isActive ?? false) ? pip?.currentStreamId : null;
    debugPrint('[${DateTime.now().toString()}] [EVENT: PIP_DEBUG] SwipeLiveScreen dispose. pipStreamId to exclude: $pipStreamId');
    
    if (activeScreenCount == 0) {
      _connectionManager.clearViewport(excludeStreamId: pipStreamId); // Singleton olduğu için çıkışta temizle
    } else {
      debugPrint('[${DateTime.now().toString()}] [EVENT: PIP_DEBUG] SwipeLiveScreen dispose skipped clearViewport because activeScreenCount is $activeScreenCount');
    }
    super.dispose();
  }

  void _flushPendingEvents() {
    if (_pendingEvents.isEmpty) return;
    final toSend = List<Map<String, dynamic>>.from(_pendingEvents);
    _pendingEvents.clear();
    StreamService.sendSwipeLiveEvents(toSend);
  }

  void _trackStreamDwell(int dwellMs) {
    _recentDwells.add(dwellMs);
    if (_recentDwells.length > 10) _recentDwells.removeAt(0);

    // Dinamik listingsPerGroup güncellemesi
    final avgMs = _recentDwells.reduce((a, b) => a + b) / _recentDwells.length;
    int newLpg = 2;
    if (avgMs > 15000) {
      newLpg = 1;
    } else if (avgMs < 3000) {
      newLpg = 3;
    } else {
      newLpg = 2;
    }

    if (_currentListingsPerGroup != newLpg) {
      setState(() {
        _currentListingsPerGroup = newLpg;
        _feedManager.updateConfig(
          streams: _feedManager.activeStreams,
          listingsPerGroup: _currentListingsPerGroup,
          preferredCategories: _preferredListingCategories,
          currentIndex: _currentPage,
        );
      });
      debugPrint('[${DateTime.now().toString()}] [EVENT: CTR_UPDATE] listingsPerGroup updated to $_currentListingsPerGroup based on avg dwell: $avgMs ms');
    }
  }

  void _onPageChanged(int page) {
    final direction = page > _currentPage ? 'SWIPE_UP' : 'SWIPE_DOWN';
    debugPrint('[${DateTime.now().toString()}] [EVENT: $direction] from index: $_currentPage to index: $page');
    if (_currentPage == page) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final prevItem = _feedManager.getItemAt(_currentPage);

    // ── Önceki sayfa yayınsa: dwell ölç ──
    if (_dwellStart != null && prevItem is LiveFeedItem) {
      final dwellMs = now - _dwellStart!;
      _trackStreamDwell(dwellMs);
      _recordStreamEvent(prevItem.stream, dwellMs);
      
      // Kullanıcı biten yayını geçiyorsa, artık o yayını feed'de ilan ile değiştir.
      // Böylece geri döndüğünde kapanmış yayın değil, yerine gelen yeni ilanı görecek.
      if (prevItem.stream.id == _polledEndedStreamId) {
        _feedManager.replaceStreamWithListing(_polledEndedStreamId!);
        _polledEndedStreamId = null;
      }
    }
    
    // ── Önceki sayfa ilansa ──
    if (_listingPageStart != null && prevItem is ListingFeedItem) {
      final dwellMs = now - _listingPageStart!;
      final isFast = dwellMs < _listingFastThresholdMs;
      if (isFast) {
        _fastListingStreak++;
      } else {
        _fastListingStreak = 0;
      }
      _recordListingEvent(prevItem.data['id'], isFast ? 'skip' : 'dwell', dwellMs: dwellMs, slotIndex: _currentPage);
    }

    setState(() {
      _currentPage = page;
    });
    _dwellStart = now;
    _listingPageStart = now;

    // Viewport hesaplama ve ConnectionManager'ı güncelleme
    _updateViewportConnections();

    // İlanlar için pagination
    if (_feedManager.needsMoreListings) {
      _loadListingFeed(loadMore: true);
    }
    
    // Canlı yayınlar için pagination (feed sona yaklaştığında)
    if (_feedManager.needsMoreLiveStreams && !_isRefreshingLive) {
      _refreshLiveStreams();
    }
    
    // Her 20 event'te batch gönder
    if (_pendingEvents.length >= 20) _flushPendingEvents();
  }

  void _updateViewportConnections() {
    debugPrint('[${DateTime.now().toString()}] [EVENT: VIEWPORT_UPDATE_CALLED] for _currentPage: $_currentPage');
    
    int activeId = -1;
    final nextIds = <int>{};
    final farIds = <int>{};

    int activeListingId = -1;
    final nextListingIds = <int>{};
    final cacheListingIds = <int>{};
    final listingUrls = <int, String>{};

    for (int i = _currentPage - 5; i <= _currentPage + 5; i++) {
      if (i < 0) continue;
      final item = _feedManager.getItemAt(i);
      if (item is LiveFeedItem) {
        final dist = (i - _currentPage).abs();
        if (dist <= 4) {
          if (dist == 0) {
            activeId = item.stream.id;
          } else if (dist <= 2) {
            nextIds.add(item.stream.id);
          } else {
            farIds.add(item.stream.id);
          }
        }
      } else if (item is ListingFeedItem) {
        final lidStr = item.data['id']?.toString() ?? '0';
        final lid = int.tryParse(lidStr) ?? 0;
        
        String? videoUrl = item.data['video_url'] as String?;
        if (videoUrl == null || videoUrl.isEmpty) {
          if (item.data['media'] != null && item.data['media'] is List) {
            final mediaList = item.data['media'] as List;
            for (final m in mediaList) {
              if (m['media_type'] == 'video') {
                videoUrl = m['media_url'];
                break;
              }
            }
          }
        }
        
        if (lid > 0 && videoUrl != null && videoUrl.isNotEmpty) {
          listingUrls[lid] = videoUrl;
          cacheListingIds.add(lid);
          
          if (i == _currentPage) {
            activeListingId = lid;
          } else if ((i - _currentPage).abs() <= 2) {
            nextListingIds.add(lid);
          }
        }
      }
    }

    // ── Eğer mevcut yayın bittiyse (Raid ekranı gösterilecekse) Raid hedeflerini prefetch et ──
    final isActiveStreamEnded = activeId > 0 && _feedManager.isStreamEnded(activeId);
    if (isActiveStreamEnded) {
      final raidTargets = _feedManager.activeStreams;
      for (int i = 0; i < raidTargets.length && i < 4; i++) {
        if (raidTargets[i].id != activeId) {
          nextIds.add(raidTargets[i].id);
        }
      }
    }

    _connectionManager.updateViewport(
      activeStreamId: activeId,
      nextStreamIds: nextIds,
      farStreamIds: farIds,
    );

    ListingVideoManager.instance.updateViewport(
      activeId: activeListingId,
      nextIds: nextListingIds,
      cacheIds: cacheListingIds,
      urls: listingUrls,
    );
  }

  void _recordStreamEvent(StreamOut stream, int dwellMs) {
    _pendingEvents.add({
      'stream_id': stream.id,
      'listing_id': 0,
      'event_type': dwellMs < 2000 ? 'skip' : 'dwell',
      'dwell_ms': dwellMs,
      'stream_category': stream.category,
      'listing_category': '',
      'listings_seen': 0,
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

  void _recordListingEvent(int listingId, String eventType, {int dwellMs = 0, String listingCategory = '', int slotIndex = 0}) {
    final streamCategory = _getCurrentStream()?.category ?? '';
    _pendingEvents.add({
      'stream_id': 0,
      'listing_id': listingId,
      'event_type': eventType,
      'dwell_ms': dwellMs,
      'stream_category': streamCategory,
      'listing_category': '',
      'listings_seen': 0,
      'slot_index': _currentPage,
      'session_id': _sessionId,
    });
  }

  void _onStreamEnded(int streamId) {
    setState(() {
      final session = _connectionManager.getSession(streamId);
      session.streamEnded = true;
      session.update();
      _feedManager.markStreamEnded(streamId);
      _polledEndedStreamId = streamId;
    });
  }

  StreamOut? _getCurrentStream() {
    final item = _feedManager.getItemAt(_currentPage);
    return item is LiveFeedItem ? item.stream : null;
  }

  Future<void> _refreshLiveStreams() async {
    if (_isRefreshingLive) return;
    try {
      _isRefreshingLive = true;
      final fresh = await StreamService.getActiveStreams();
      if (mounted) {
        setState(() {
          _feedManager.updateConfig(
            streams: fresh,
            listingsPerGroup: _currentListingsPerGroup,
            preferredCategories: _preferredListingCategories,
            currentIndex: _currentPage,
          );
        });
        _updateViewportConnections();
      }
    } catch (_) {
    } finally {
      if (mounted) _isRefreshingLive = false;
    }
  }

  Future<void> _expandFromSingleMode(int targetId) async {
    try {
      final fresh = await StreamService.getActiveStreams();
      final target = fresh.firstWhere(
        (s) => s.id == targetId,
        orElse: () => widget.streams[0],
      );
      final others = fresh.where((s) => s.id != targetId).toList();
      final expanded = [target, ...others];
      setState(() {
        _feedManager.updateConfig(
          streams: expanded,
          listingsPerGroup: _currentListingsPerGroup,
          preferredCategories: _preferredListingCategories,
          currentIndex: _currentPage,
        );
      });
      _loadListingFeed();
    } catch (_) {}
  }

  Future<void> _loadListingFeed({bool loadMore = false}) async {
    if (_fetchingListings || !_hasMoreListings) return;
    _fetchingListings = true;
    try {
      if (loadMore) {
        _listingPage++;
      } else {
        _listingPage = 0;
      }
      
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/swipe-feed?limit=10&page=$_listingPage'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (resp.statusCode != 200) {
        if (loadMore) _listingPage--;
        return;
      }
      
      final List<dynamic> raw = jsonDecode(resp.body) as List<dynamic>;
      if (raw.isEmpty) {
        _hasMoreListings = false;
        if (!mounted) return;
      }
      
      if (!mounted) return;
      setState(() {
        final newItems = raw.cast<Map<String, dynamic>>();
        if (_preferredListingCategories.isNotEmpty) {
          newItems.sort((a, b) {
            final catA = a['category']?.toString() ?? '';
            final catB = b['category']?.toString() ?? '';
            final rankA = _preferredListingCategories.indexOf(catA);
            final rankB = _preferredListingCategories.indexOf(catB);
            return (rankA < 0 ? 999 : rankA).compareTo(rankB < 0 ? 999 : rankB);
          });
        }
        _feedManager.addListings(newItems);
      });
      // Feed güncellendiyse (viewport'a ilan girdiyse) videoları pre-initialize et
      _updateViewportConnections();
    } catch (e) {
      debugPrint('[SwipeLive] listing feed hata: $e');
      if (loadMore) _listingPage--;
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
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (info) {
          if (info.metrics.axis == Axis.vertical) {
            final page = _pageCtrl.page;
            if (page != null) {
              final isDragging = (page - page.roundToDouble()).abs() > 0.01;
              final activeItem = _feedManager.getItemAt(_currentPage);
              if (activeItem is ListingFeedItem) {
                final lidStr = activeItem.data['id']?.toString() ?? '0';
                final lid = int.tryParse(lidStr) ?? 0;
                final ctrl = ListingVideoManager.instance.getController(lid);
                if (isDragging) {
                  ctrl?.setVolume(0.0); // Kaydırma anında sesi şak diye kes
                } else {
                  ctrl?.setVolume(1.0); // Bırakırsa geri aç
                }
              }
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageCtrl,
          scrollDirection: Axis.vertical,
          physics: _isCoHostLocked ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          onPageChanged: _onPageChanged,
          itemCount: null,
          itemBuilder: (_, i) {
            final item = _feedManager.getItemAt(i);
          return switch (item) {
            LiveFeedItem(:final stream) => _SwipeLivePage(
                key: ValueKey('live_${stream.id}_$i'),
                stream: stream,
                session: _connectionManager.getSession(stream.id),
                isActive: i == _currentPage,
                isEnded: _feedManager.isStreamEnded(stream.id),
                onStreamEnded: () => _onStreamEnded(stream.id),
                onPipActionChanged: (cb) { _pipAction = cb; },
                onEngagementEvent: (type) => _recordEngagementEvent(stream, type),
                onCoHostStateChanged: (locked) {
                  if (mounted && _isCoHostLocked != locked) {
                    setState(() => _isCoHostLocked = locked);
                  }
                },
                onRaidTargetSelected: (targetId) {
                  final targetPage = _feedManager.getNextPageForStreamId(targetId, _currentPage);
                  if (targetPage != null) {
                    _pageCtrl.jumpToPage(targetPage);
                  }
                },
              ),
            ListingFeedItem(:final data) => _ListingVideoPage(
                key: ValueKey('listing_${data['id']}_$i'),
                listing: data,
                isActive: i == _currentPage,
                slotIndex: i,
                streamCategory: _getCurrentStream()?.category ?? '',
                onSwipeLiveEvent: _recordListingEvent,
              ),
            LoadingFeedItem() => ColoredBox(
                key: ValueKey('loading_$i'),
                color: Colors.black,
              ),
          };
        },
      ),
      ),
      ),
    );
  }
}

// ── Tek yayın sayfası ────────────────────────────────────────────────────────

class _SwipeLivePage extends ConsumerStatefulWidget {
  final StreamOut stream;
  final LiveSession session;
  final bool isActive;
  final VoidCallback? onStreamEnded;
  final void Function(VoidCallback?)? onPipActionChanged;
  final void Function(String eventType)? onEngagementEvent;
  final void Function(int targetStreamId)? onRaidTargetSelected;
  final ValueChanged<bool>? onCoHostStateChanged;
  final bool isEnded;

  const _SwipeLivePage({
    super.key,
    required this.stream,
    required this.session,
    required this.isActive,
    this.isEnded = false,
    this.onStreamEnded,
    this.onPipActionChanged,
    this.onEngagementEvent,
    this.onRaidTargetSelected,
    this.onCoHostStateChanged,
  });

  @override
  ConsumerState<_SwipeLivePage> createState() => _SwipeLivePageState();
}

class _SwipeLivePageState extends ConsumerState<_SwipeLivePage>
    with AutomaticKeepAliveClientMixin {
  
  bool _isCoHost = false;
  bool _isSelfCoHostValue = false;
  bool get _isSelfCoHost => _isSelfCoHostValue;
  set _isSelfCoHost(bool val) {
    if (_isSelfCoHostValue != val) {
      _isSelfCoHostValue = val;
      if (widget.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onCoHostStateChanged?.call(val);
        });
      }
    }
  }

  bool _selfMuted = false;
  bool _kicked = false;
  
  double? _pipTop;
  double? _pipLeft;
  final Set<String> _coHostMutedUsers = {};
  final _heartsKey = GlobalKey<FloatingHeartsState>();
  Timer? _likeThrottleTimer;
  bool _likeThrottlePending = false;
  
  LocalVideoTrack? _localVideoTrack;
  int _viewerCount = 0;
  String? _myUsername;
  // single() modunda token geldikten sonra doldurulur
  String? _resolvedTitle;
  String? _resolvedHostUsername;
  
  // Kazanan konfetisi
  late ConfettiController _confettiController;
  // Hediye HUD overlay
  OverlayEntry? _giftHudEntry;
  Timer? _giftHudTimer;
  final _hypeScore = ValueNotifier<int>(0);

  @override
  bool get wantKeepAlive => widget.session.isConnected;

  @override
  void initState() {
    super.initState();
    StorageService.getUserInfo().then((info) {
      if (mounted && info != null) {
        setState(() => _myUsername = info['username'] as String?);
      }
    });
    
    // Eğer oturum daha önceden yetkilendirilmişse (örn: PiP'den dönüldüğünde)
    // Co-host state'ini mevcut session'dan geri yükle
    if (widget.session.localVideoTrack != null) {
      _isSelfCoHost = true;
      _localVideoTrack = widget.session.localVideoTrack;
    }
    
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    widget.session.addListener(_onSessionUpdated);
    if (widget.isActive) {
      widget.onPipActionChanged?.call(_pipForBackGesture);
    }
  }

  @override
  void didUpdateWidget(_SwipeLivePage old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      if (!old.session.isDisposed) {
        old.session.removeListener(_onSessionUpdated);
      }
      widget.session.addListener(_onSessionUpdated);
    }
    
    if (widget.isActive && !old.isActive) {
      widget.onPipActionChanged?.call(_pipForBackGesture);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCoHostStateChanged?.call(_isSelfCoHost);
      });
      if (widget.session.isConnected) {
        AnalyticsService.logInteraction(
          itemId: widget.stream.id,
          itemType: 'stream',
          interactionType: 'swipe_impression',
        );
      }
    } else if (!widget.isActive && old.isActive) {
      widget.onPipActionChanged?.call(null);
    }
  }

  void _onSessionUpdated() {
    if (!mounted) return;

    if (widget.session.localVideoTrack != null && (_localVideoTrack == null || !_isSelfCoHost)) {
      _isSelfCoHost = true;
      _localVideoTrack = widget.session.localVideoTrack;
    }

    setState(() {});
    updateKeepAlive();
    
    if (_resolvedTitle == null && widget.session.token != null) {
      setState(() {
        _resolvedTitle = widget.session.token?.title;
        _resolvedHostUsername = widget.session.token?.hostUsername;
      });
    }
  }

  @override
  void dispose() {
    if (!widget.session.isDisposed) {
      widget.session.removeListener(_onSessionUpdated);
    }
    _confettiController.dispose();
    _giftHudTimer?.cancel();
    _giftHudEntry?.remove();
    _hypeScore.dispose();
    _likeThrottleTimer?.cancel();
    super.dispose();
  }

  void _showGiftHud(String sender, String giftName, int cost) {
    if (!mounted || !widget.isActive) return;
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
        onLoadBalanceRequired: () {
          Navigator.pop(ctx);
          _handleLoadBalance();
        },
      ),
    );
  }

  void _handleLoadBalance() {
    // 1. Get the root navigator before we are popped by PiP
    final nav = Navigator.of(context, rootNavigator: true);
    // 2. Enter PiP (which also pops the current SwipeLiveScreen)
    _enterPip();
    // 3. Push the Wallet screen on top
    nav.push(MaterialPageRoute(builder: (_) => const WalletScreen()));
  }

  void _onAuctionWon() {
    if (!widget.isActive) return;
    _confettiController.play();
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), HapticFeedback.vibrate);
  }

  void _handleMuted() {
    if (!mounted) return;
    setState(() => _selfMuted = true);
    if (!widget.isActive) return;
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
    if (!widget.isActive) return;
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
    widget.session.room?.disconnect();
    if (!widget.isActive) return;
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
    if (!widget.isActive) return;
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
    if (!widget.isActive) return;
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
    if (!widget.isActive) return;
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
    StreamConnectionManager.instance.downgradeFromCoHost(widget.stream.id);
    setState(() {
      _isSelfCoHost = false;
      _localVideoTrack = null;
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
    try {
      final newToken = await StreamService.acceptCoHostInvite(widget.stream.id);
      await StreamConnectionManager.instance.upgradeToCoHost(widget.stream.id, newToken);
      if (mounted) {
        setState(() {
          _isSelfCoHost = true;
          _localVideoTrack = widget.session.localVideoTrack;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
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
    widget.onStreamEnded?.call();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  // iOS back gesture veya ← button'dan PiP kurulumu (senkron)
  void _pipForBackGesture() {
    final track = widget.session.hostVideoTrack;
    final room = widget.session.room;
    if (track == null || room == null) return; // Video yok, PiP açılamaz

    debugPrint('[${DateTime.now().toString()}] [EVENT: PIP_DEBUG] _pipForBackGesture called for stream: ${widget.stream.id}');
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
    final track = widget.session.hostVideoTrack;
    final room = widget.session.room;
    if (track == null || room == null) {
      await _leave();
      return;
    }
    _pipForBackGesture();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _handleRaid(int targetStreamId) async {
    widget.onEngagementEvent?.call('raid_chose');
    
    // SwipeLive'da baskın seçildi — uygulamadan çıkma, biten yayını listeden çıkar
    widget.onStreamEnded?.call();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin için gerekli
    final l = AppLocalizations.of(context)!;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final hasThumbnail =
        widget.stream.thumbnailUrl != null && widget.stream.thumbnailUrl!.isNotEmpty;

    if (widget.isEnded) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LIVE_UI_ENDED_OVERLAY] Showing RaidEndedOverlay for stream: ${widget.stream.id}');
      return RaidEndedOverlay(
        streamId: widget.stream.id,
        hostUsername: widget.stream.host.username,
        onClose: () {
          if (Navigator.canPop(context)) Navigator.pop(context);
        },
        onRaid: (targetStreamId) {
          debugPrint('[${DateTime.now().toString()}] [EVENT: LIVE_UI_RAID_JOINED] User clicked Raid Target: $targetStreamId');
          widget.onRaidTargetSelected?.call(targetStreamId);
        },
      );
    }
    
    if (widget.session.room == null) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LIVE_UI_LOADING] Showing FullScreenLoading for stream: ${widget.stream.id}');
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    debugPrint('[${DateTime.now().toString()}] [EVENT: LIVE_UI_ACTIVE] Showing LIVE ROOM for stream: ${widget.stream.id}');
    return Stack(
      children: [
        // ── Arka plan: video veya thumbnail ──────────────────────────────
        if (widget.session.hostVideoTrack != null)
          Positioned.fill(
            child: VideoTrackRenderer(
              widget.session.hostVideoTrack!,
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
        if (widget.session.isConnecting)
          Positioned.fill(
            child: ColoredBox(
              color: hasThumbnail ? Colors.black38 : Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: kPrimary)),
            ),
          ),

        // ── Yayın sona erdi overlay ─────────────────────────────────────────
        if (widget.session.streamEnded || widget.isEnded)
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
            viewerCount: widget.stream.viewerCount,
            title: _resolvedTitle ?? widget.stream.title,
            hostUsername: _resolvedHostUsername ?? widget.stream.host.username,
            isCoHost: _isCoHost,
            streamEnded: widget.session.streamEnded || widget.isEnded,
            onLeave: _leave,
            onEnterPip: (widget.session.streamEnded || widget.isEnded) ? null : _enterPip,
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
                        key: ValueKey(_localVideoTrack.hashCode),
                        fit: VideoViewFit.contain,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () async {
                            final sid = widget.session.token?.streamId;
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
        else if (!_isSelfCoHost && widget.session.coHostVideoTrack != null)
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
                    widget.session.coHostVideoTrack!,
                    fit: VideoViewFit.contain,
                    mirrorMode: VideoViewMirrorMode.mirror,
                  ),
                ),
              ),
            ),
          ),

        if (!widget.session.streamEnded && !widget.isEnded)
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
        if (widget.isActive && widget.session.token != null && !widget.session.streamEnded && !widget.isEnded)
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
                      widget.onStreamEnded?.call();
                      if (widget.isActive) {
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
                  if ((widget.session.token?.category ?? widget.stream.category) != 'sohbet')
                    AuctionPanel(
                      streamId: widget.stream.id,
                      isHost: false,
                      isCoHost: _isCoHost,
                      enabled: !_selfMuted,
                      hostUserId: int.tryParse(widget.session.token?.hostLivekitIdentity ?? ''),
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
  final VoidCallback? onLoadBalanceRequired;

  const _GiftSheet({
    required this.streamId,
    required this.receiverUsername,
    required this.gifts,
    this.onLoadBalanceRequired,
  });

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  bool _sending = false;
  bool _insufficientBalance = false;

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
      final isInsufficient = result['status_code'] == 402 || 
          (result['error']?.toString().toLowerCase().contains('yetersiz') ?? false);
          
      if (isInsufficient) {
        setState(() => _insufficientBalance = true);
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
          else if (_insufficientBalance)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)?.giftInsufficientBalance ?? 'Bakiyeniz yetersiz. Hediye göndermek için TUCi satın alın.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: widget.onLoadBalanceRequired,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D28D9),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    child: Text(
                      AppLocalizations.of(context)?.giftLoadBalanceButton ?? 'Bakiye Yükle',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
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
  // Parent'tan gelen swipe_live_events yazıcısı — LPG CTR hesabı için
  final void Function(int listingId, String eventType, {int dwellMs, String listingCategory, int slotIndex})? onSwipeLiveEvent;

  const _ListingVideoPage({
    super.key,
    required this.listing,
    required this.isActive,
    this.slotIndex = 0,
    this.streamCategory = '',
    this.onSwipeLiveEvent,
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
    final lidInt = int.tryParse(lid) ?? 0;
    final category = (widget.listing['category'] as String?) ?? '';
    final hasVideo = (widget.listing['video_url'] as String?) != null &&
        (widget.listing['video_url'] as String).isNotEmpty;

    // feed_analytics'e yaz (FeedTelemetryService — mevcut)
    FeedTelemetryService.instance.logEvent(
      listingId: lid,
      eventType: ms < 2000 ? 'skip' : 'impression',
      dwellTimeMs: ms,
      contentType: hasVideo ? 'video' : 'photo',
      slotIndex: widget.slotIndex,
      streamCategory: widget.streamCategory,
    );

    // swipe_live_events'e de yaz — LPG CTR hesabının veri kaynağı
    if (lidInt > 0) {
      widget.onSwipeLiveEvent?.call(
        lidInt,
        ms < 2000 ? 'listing_skip' : 'listing_impression',
        dwellMs: ms,
        listingCategory: category,
        slotIndex: widget.slotIndex,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _startWatch();
    _initVideo();
  }

  Future<void> _initVideo() async {
    debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_INIT_STARTED] for listing: ${widget.listing['id']}');
    String? videoUrl = widget.listing['video_url'] as String?;
    if (videoUrl == null || videoUrl.isEmpty) {
      if (widget.listing['media'] != null && widget.listing['media'] is List) {
        final mediaList = widget.listing['media'] as List;
        for (final m in mediaList) {
          if (m['media_type'] == 'video') {
            videoUrl = m['media_url'];
            break;
          }
        }
      }
    }

    if (videoUrl == null || videoUrl.isEmpty) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_NO_VIDEO_URL] for listing: ${widget.listing['id']}');
      if (mounted) setState(() => _initialized = true);
      return;
    }
    
    final lidStr = widget.listing['id']?.toString() ?? '0';
    final lidInt = int.tryParse(lidStr) ?? 0;
    
    _ctrl = ListingVideoManager.instance.getOrCreateController(lidInt, videoUrl);
    
    if (_ctrl!.value.isInitialized) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_INSTANT_PLAY_READY] Video already initialized for: $lidInt');
      setState(() => _initialized = true);
    } else {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_WAITING_INIT] Waiting for video initialization for: $lidInt');
      void listener() {
        if (_ctrl?.value.isInitialized ?? false) {
          debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_INIT_CALLBACK] Video initialized for: $lidInt');
          _ctrl?.removeListener(listener);
          if (mounted) {
            setState(() => _initialized = true);
            if (widget.isActive) {
              debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_AUTO_PLAYING] Autoplaying after init for: $lidInt');
              _ctrl?.setVolume(1.0);
              _ctrl?.play();
            }
          }
        }
      }
      _ctrl!.addListener(listener);
    }
    
    if (widget.isActive && _initialized) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_AUTO_PLAYING] Autoplaying instantly for: $lidInt');
      _ctrl!.setVolume(1.0);
      _ctrl!.play();
    }
  }

  @override
  void didUpdateWidget(_ListingVideoPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_BECAME_ACTIVE] for listing: ${widget.listing['id']}');
      if (_initialized) {
        debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_PLAY_COMMAND] Playing video for listing: ${widget.listing['id']}');
        _ctrl?.setVolume(1.0);
        _ctrl?.play();
      } else {
        debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_ACTIVE_BUT_NOT_READY] Video NOT INITIALIZED YET for listing: ${widget.listing['id']}');
      }
      _startWatch();
    } else if (!widget.isActive && old.isActive) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_BECAME_INACTIVE] for listing: ${widget.listing['id']}');
      _ctrl?.pause();
      _stopAndLog();
    }
  }

  @override
  void dispose() {
    _stopAndLog();
    _ctrl?.pause(); // Oynatma sürüyorsa kapat
    // _ctrl, ListingVideoManager tarafından dispose edilecektir (fallback harici ama şimdilik okey)
    super.dispose();
  }

  void _goToListing() {
    // Detay ekranı açılmadan önce videoyu durdur
    _ctrl?.pause();
    final hasVideo = (widget.listing['video_url'] as String?) != null &&
        (widget.listing['video_url'] as String).isNotEmpty;
    final lid = (widget.listing['id'] ?? '').toString();
    final lidInt = int.tryParse(lid) ?? 0;
    final category = (widget.listing['category'] as String?) ?? '';
    final dwellMs = _stopwatch.elapsedMilliseconds;

    // feed_analytics'e tıklama yaz
    FeedTelemetryService.instance.logEvent(
      listingId: lid,
      eventType: 'click',
      dwellTimeMs: dwellMs,
      contentType: hasVideo ? 'video' : 'photo',
      slotIndex: widget.slotIndex,
      streamCategory: widget.streamCategory,
    );

    // swipe_live_events'e de yaz — LPG CTR için
    if (lidInt > 0) {
      widget.onSwipeLiveEvent?.call(
        lidInt,
        'listing_tap',
        dwellMs: dwellMs,
        listingCategory: category,
        slotIndex: widget.slotIndex,
      );
    }

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
          if (_initialized && _ctrl != null) ...[
            Builder(builder: (_) {
              debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_BUILD_READY] Showing VIDEO PLAYER for listing: ${listing['id']}');
              return FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _ctrl!.value.size.width,
                  height: _ctrl!.value.size.height,
                  child: VideoPlayer(_ctrl!),
                ),
              );
            })
          ] else if (thumbUrl.isNotEmpty) ...[
            Builder(builder: (_) {
              debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_BUILD_FALLBACK] Showing THUMBNAIL for listing: ${listing['id']}');
              return CachedNetworkImage(imageUrl: imgUrl(thumbUrl), fit: BoxFit.cover);
            })
          ] else ...[
            Builder(builder: (_) {
              debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_UI_BUILD_LOADING] Showing BLACK SCREEN for listing: ${listing['id']}');
              return const ColoredBox(color: Colors.black);
            })
          ],

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
