import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

class PipProvider extends ChangeNotifier {
  bool _isActive = false;
  int? _currentStreamId;
  String? _currentRoomName;
  String? _hostUsername;
  Room? _room;
  VideoTrack? _track;

  bool get isActive => _isActive;
  int? get currentStreamId => _currentStreamId;
  String? get currentRoomName => _currentRoomName;
  String? get hostUsername => _hostUsername;
  VideoTrack? get track => _track;

  void enablePip({
    required int streamId,
    required String roomName,
    required String hostUsername,
    required Room room,
    required VideoTrack track,
  }) {
    _isActive = true;
    _currentStreamId = streamId;
    _currentRoomName = roomName;
    _hostUsername = hostUsername;
    _room = room;
    _track = track;
    _setRemoteVideoQuality(room, VideoQuality.LOW);
    notifyListeners();
  }

  void disablePip({bool disconnectRoom = true}) {
    debugPrint('[${DateTime.now().toString()}] [EVENT: PIP_DEBUG] disablePip called. disconnectRoom: $disconnectRoom');
    if (disconnectRoom) {
      _room?.disconnect();
    } else if (_room != null) {
      // Tam ekrana genişletme — kalite sınırını kaldır
      _setRemoteVideoQuality(_room!, VideoQuality.HIGH);
    }
    _isActive = false;
    _currentStreamId = null;
    _currentRoomName = null;
    _hostUsername = null;
    _room = null;
    _track = null;
    notifyListeners();
  }

  void _setRemoteVideoQuality(Room room, VideoQuality quality) {
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        pub.setVideoQuality(quality).ignore();
      }
    }
  }
}

final pipProvider = ChangeNotifierProvider<PipProvider>((ref) => PipProvider());
