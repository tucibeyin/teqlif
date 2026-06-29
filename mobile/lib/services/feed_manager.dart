import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/stream.dart';

sealed class FeedItem {
  const FeedItem();
}
class LiveFeedItem extends FeedItem {
  final StreamOut stream;
  const LiveFeedItem(this.stream);
}
class ListingFeedItem extends FeedItem {
  final Map<String, dynamic> data;
  const ListingFeedItem(this.data);
}
class LoadingFeedItem extends FeedItem {
  const LoadingFeedItem();
}

class FeedSlot {
  final bool isStream;
  final int streamId;
  final int listingId;
  FeedSlot.stream(this.streamId) : isStream = true, listingId = -1;
  FeedSlot.listing(this.listingId) : isStream = false, streamId = -1;
}

/// FeedManager, canlı yayınlar ve ilanların TikTok tarzı dikey akışta
/// (ML skorlarına ve CTR'a göre) harmanlanmasını sağlar.
class SwipeFeedManager {
  List<StreamOut> _liveItems = [];
  final List<Map<String, dynamic>> _listingPool = [];
  
  int _listingsPerGroup = 2;
  
  final List<FeedSlot> _slots = [];
  int _nextListingIndex = 0;
  int _nextStreamIndex = 0;
  int _listingOnlyGroupCount = 0;

  final Set<int> _endedStreamIds = {};
  final List<int> _priorityStreamIds = [];
  final Set<int> _shownStreamIds = {};

  bool get needsMoreListings => _listingPool.isNotEmpty && _nextListingIndex >= _listingPool.length - 5;
  List<StreamOut> get activeStreams => _liveItems.where((s) => !_endedStreamIds.contains(s.id)).toList();

  void init({
    required List<StreamOut> initialStreams,
    required int initialIndex,
  }) {
    _liveItems = initialStreams;
    // initialIndex'e kadar olan grupları üret ki geri kaydırmada sorun olmasın
    _extendGroupsUpTo((initialIndex + 1) * 10);
  }

  void updateConfig({
    required List<StreamOut> streams,
    required int listingsPerGroup,
    required List<String> preferredCategories,
    required int currentIndex,
  }) {
    debugPrint('[${DateTime.now().toString()}] [EVENT: FEED_UPDATE] streams: ${streams.length} | listingsPerGroup: $listingsPerGroup');
    _listingsPerGroup = listingsPerGroup;
    
    // Sadece henüz bitmemiş yeni yayınları al
    final freshIds = streams.map((s) => s.id).toSet();
    
    // Eski listede olup yeni listede olmayanlar (bitti)
    final newLiveItems = <StreamOut>[];
    for (final s in _liveItems) {
      if (!freshIds.contains(s.id)) {
        debugPrint('[${DateTime.now().toString()}] [EVENT: STREAM_ENDED] Stream not in freshIds, keeping in feed: ${s.id}');
        _endedStreamIds.add(s.id);
        newLiveItems.add(s); // Kullanıcı hala bu sayfada olabilir, listeden çıkarma!
      } else {
        // Güncel veriyi al
        newLiveItems.add(streams.firstWhere((x) => x.id == s.id));
      }
    }
    
    final newlyAddedStreams = <StreamOut>[];
    
    // Yepyeni yayınları ekle
    for (final s in streams) {
      if (!_liveItems.any((old) => old.id == s.id)) {
        debugPrint('[${DateTime.now().toString()}] [EVENT: STREAM_ADDED] New stream added: ${s.id}');
        newLiveItems.add(s);
        newlyAddedStreams.add(s);
      }
    }
    
    _liveItems = newLiveItems;
    
    // Yeni eklenen yayınları priority kuyruğuna ekle ki bir sonraki FeedSlot üretilirken öncelikli seçilsinler
    for (final s in newlyAddedStreams) {
      if (!_priorityStreamIds.contains(s.id)) {
        _priorityStreamIds.add(s.id);
      }
    }
    
    // Gelecekteki önbelleğe alınmış slotları temizle ki yeni yayın 10-15 swipe sonraya kalmasın.
    // O anki swipe animasyonunu bozmamak için kullanıcının bulunduğu +1 sonrasını koruyoruz.
    if (newlyAddedStreams.isNotEmpty && _slots.length > currentIndex + 2) {
      _slots.removeRange(currentIndex + 2, _slots.length);
    }
    
    debugPrint('[${DateTime.now().toString()}] [EVENT: FEED_UPDATE_COMPLETE] _liveItems: ${_liveItems.length} | endedStreamIds: $_endedStreamIds');
  }

  void addListings(List<Map<String, dynamic>> newListings) {
    debugPrint('[${DateTime.now().toString()}] [EVENT: LISTINGS_ADDED] Count: ${newListings.length} | pool_size_before: ${_listingPool.length}');
    _listingPool.addAll(newListings);
  }

  void markStreamEnded(int streamId) {
    debugPrint('[${DateTime.now().toString()}] [EVENT: STREAM_MARKED_ENDED] streamId: $streamId');
    _endedStreamIds.add(streamId);
  }
  
  void removeStream(int streamId) {
    debugPrint('[${DateTime.now().toString()}] [EVENT: STREAM_REMOVED] streamId: $streamId');
    _liveItems.removeWhere((s) => s.id == streamId);
    _endedStreamIds.add(streamId);
  }
  
  bool isStreamEnded(int streamId) => _endedStreamIds.contains(streamId);

  FeedItem getItemAt(int index) {
    if (index >= _slots.length) {
      _extendGroupsUpTo(index + 5);
    }
    
    final slot = _slots[index];
    if (slot.isStream) {
      if (_liveItems.isEmpty) return const LoadingFeedItem();
      final stream = _liveItems.firstWhere((s) => s.id == slot.streamId, orElse: () => _liveItems.first);
      return LiveFeedItem(stream);
    } else {
      if (_listingPool.isEmpty) return const LoadingFeedItem();
      final lIndex = slot.listingId % _listingPool.length;
      return ListingFeedItem(_listingPool[lIndex]);
    }
  }

  int getPageForLiveIndex(int liveIndex) {
    if (liveIndex <= 0) return 0;
    int streamCount = 0;
    int i = 0;
    while (true) {
      if (i >= _slots.length) _extendGroupsUpTo(_slots.length + 10);
      if (_slots[i].isStream) {
        if (streamCount == liveIndex) return i;
        streamCount++;
      }
      i++;
    }
  }

  int? getNextPageForStreamId(int streamId, int currentIndex) {
    final activeCount = _liveItems.where((s) => !_endedStreamIds.contains(s.id)).length;
    if (activeCount == 0) return null;
    
    _extendGroupsUpTo(currentIndex + (activeCount * 5));
    
    for (int i = currentIndex; i < _slots.length; i++) {
      if (_slots[i].isStream && _slots[i].streamId == streamId) {
        return i;
      }
    }
    return null;
  }

  void _extendGroupsUpTo(int targetPage) {
    final rand = Random();
    while (_slots.length <= targetPage) {
      int? streamId;
      final activeStreams = _liveItems.where((s) => !_endedStreamIds.contains(s.id)).toList();
      final unshownStreams = activeStreams.where((s) => !_shownStreamIds.contains(s.id)).toList();
      
      if (_priorityStreamIds.isNotEmpty) {
        streamId = _priorityStreamIds.removeAt(0);
      } else if (unshownStreams.isNotEmpty) {
        streamId = unshownStreams[_nextStreamIndex % unshownStreams.length].id;
        _nextStreamIndex++;
      } else if (activeStreams.isNotEmpty) {
        // Tüm yayınlar gösterildiyse, başa sarıp tekrar göster
        streamId = activeStreams[_nextStreamIndex % activeStreams.length].id;
        _nextStreamIndex++;
      }
      
      if (streamId != null) {
        _shownStreamIds.add(streamId);
        _slots.add(FeedSlot.stream(streamId));
        debugPrint('[${DateTime.now().toString()}] [EVENT: GROUP_EXTENDED] streamAt: ${_slots.length - 1}');
      }

      int listingsInThisGroup = _listingsPerGroup;
      if (streamId == null) {
        // Yayın kalmadıysa mecbur ilan göstereceğiz
        listingsInThisGroup = _listingsPerGroup > 0 ? _listingsPerGroup : 2;
      } else {
        if (_listingOnlyGroupCount >= 2) {
          listingsInThisGroup = 0;
          _listingOnlyGroupCount = 0;
        } else if (rand.nextDouble() < 0.2) {
          listingsInThisGroup = 0;
          _listingOnlyGroupCount++;
        } else if (rand.nextDouble() < 0.3) {
          listingsInThisGroup = _listingsPerGroup + 1;
          _listingOnlyGroupCount = 0;
        } else {
          _listingOnlyGroupCount = 0;
        }
      }

      for (int i = 0; i < listingsInThisGroup; i++) {
        _slots.add(FeedSlot.listing(_nextListingIndex++));
      }
    }
  }
}
