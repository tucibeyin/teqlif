import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../services/analytics_service.dart';
import '../../../services/auction_service.dart';
import '../../../services/moderation_service.dart';
import '../../../services/stream_service.dart';


class HostStreamViewModel {
  // Analytics
  Future<Map<String, dynamic>?> getAudienceSize(String title, String category) async {
    try {
      return await AnalyticsService.getAudienceSize(title: title, category: category);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> sendLeadBlast(String title, String category, int estimatedCost) async {
    try {
      return await AnalyticsService.sendLeadBlast(
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
      return await AuctionService.fetchBids(streamId);
    } catch (_) {
      return [];
    }
  }

  // Moderation
  Future<bool> promoteUser(int streamId, String username) async {
    try {
      await ModerationService.promoteUser(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> demoteUser(int streamId, String username) async {
    try {
      await ModerationService.demoteUser(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> muteUser(int streamId, String username) async {
    try {
      await ModerationService.mute(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unmuteUser(int streamId, String username) async {
    try {
      await ModerationService.unmute(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> kickUser(int streamId, String username) async {
    try {
      await ModerationService.kick(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Stream Actions
  Future<void> confirmLive(int streamId) async {
    await StreamService.confirmLive(streamId);
  }

  Future<void> endStream(int streamId) async {
    await StreamService.endStream(streamId);
  }

  Future<void> cancelStream(int streamId) async {
    await StreamService.cancelStream(streamId);
  }

  Future<Map<String, dynamic>?> fetchAudienceInsights(int streamId) async {
    try {
      return await StreamService.fetchAudienceInsights(streamId);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> getViewers(int streamId) async {
    try {
      return await StreamService.getViewers(streamId);
    } catch (_) {
      return [];
    }
  }

  Future<bool> inviteCoHost(int streamId, String username) async {
    try {
      await StreamService.inviteCoHost(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeCoHost(int streamId, String username) async {
    try {
      await StreamService.removeCoHost(streamId, username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> uploadThumbnail(int streamId, Uint8List imageBytes) async {
    try {
      await StreamService.uploadThumbnail(streamId, imageBytes, 'thumb.png');
      return true;
    } catch (_) {
      return false;
    }
  }
}

final hostStreamViewModelProvider = Provider<HostStreamViewModel>((ref) {
  return HostStreamViewModel();
});
