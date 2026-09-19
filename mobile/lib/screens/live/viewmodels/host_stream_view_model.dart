import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../services/analytics_service.dart';
import '../../../services/auction_service.dart';
import '../../../services/moderation_service.dart';
import '../../../services/stream_service.dart';


class HostStreamViewModel {
  final AnalyticsService _analytics;
  final AuctionService _auction;
  final ModerationService _moderation;
  final StreamService _stream;

  HostStreamViewModel(this._analytics, this._auction, this._moderation, this._stream);

  // Analytics
  Future<Map<String, dynamic>?> getAudienceSize(String title, String category) async {
    try {
      return await _analytics.getAudienceSize(title: title, category: category);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> sendLeadBlast(String title, String category, int estimatedCost) async {
    try {
      return await _analytics.sendLeadBlast(
        title: title,
        category: category,
        estimatedCost: estimatedCost,
      );
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Auction
  Future<List<Map<String, dynamic>>> fetchBids(int streamId) async {
    try {
      return await _auction.fetchBids(streamId);
    } catch (_) {
      return [];
    }
  }

  // Moderation
  Future<bool> promoteUser(int streamId, String username) async {
    try {
      await _moderation.promoteUser(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> demoteUser(int streamId, String username) async {
    try {
      await _moderation.demoteUser(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> muteUser(int streamId, String username) async {
    try {
      await _moderation.mute(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unmuteUser(int streamId, String username) async {
    try {
      await _moderation.unmute(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> kickUser(int streamId, String username) async {
    try {
      await _moderation.kick(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Stream Actions
  Future<void> confirmLive(int streamId) async {
    await _stream.confirmLive(streamId);
  }

  Future<void> endStream(int streamId) async {
    await _stream.endStream(streamId);
  }

  Future<void> cancelStream(int streamId) async {
    await _stream.cancelStream(streamId);
  }

  Future<Map<String, dynamic>?> fetchAudienceInsights(int streamId) async {
    try {
      return await _stream.fetchAudienceInsights(streamId);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getViewers(int streamId) async {
    try {
      return await _stream.getViewers(streamId);
    } catch (_) {
      return [];
    }
  }

  Future<bool> inviteCoHost(int streamId, String username) async {
    try {
      await _stream.inviteCoHost(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeCoHost(int streamId, String username) async {
    try {
      await _stream.removeCoHost(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> uploadThumbnail(int streamId, Uint8List imageBytes) async {
    try {
      await _stream.uploadThumbnail(streamId, imageBytes, 'thumb.png');
      return true;
    } catch (_) {
      return false;
    }
  }
}

final hostStreamViewModelProvider = Provider<HostStreamViewModel>((ref) {
  return HostStreamViewModel(
    ref.watch(analyticsServiceProvider),
    ref.watch(auctionServiceProvider),
    ref.watch(moderationServiceProvider),
    ref.watch(streamServiceProvider),
  );
});
