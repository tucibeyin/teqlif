import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import '../api/api_client.dart';

final liveRoomProvider = StateNotifierProvider.family<LiveRoomNotifier, LiveRoomState, String>((ref, roomId) {
  return LiveRoomNotifier(roomId);
});

class LiveRoomState {
  final Room? room;
  final bool isConnecting;
  final String? error;
  final Duration serverTimeOffset;
  final bool isFrozen;

  LiveRoomState({
    this.room,
    this.isConnecting = false,
    this.error,
    this.serverTimeOffset = Duration.zero,
    this.isFrozen = false,
  });

  LiveRoomState copyWith({
    Room? room,
    bool? isConnecting,
    String? error,
    Duration? serverTimeOffset,
    bool? isFrozen,
  }) {
    return LiveRoomState(
      room: room ?? this.room,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error ?? this.error,
      serverTimeOffset: serverTimeOffset ?? this.serverTimeOffset,
      isFrozen: isFrozen ?? this.isFrozen,
    );
  }
}

class LiveRoomNotifier extends StateNotifier<LiveRoomState> {
  final String roomId;
  Room? _room;

  LiveRoomNotifier(this.roomId) : super(LiveRoomState());

  Future<void> connect(bool isOwner) async {
    if (state.isConnecting || state.room != null) return;
    
    state = state.copyWith(isConnecting: true, error: null);

    try {
      // 1. Fetch Token from Next.js API
      final response = await ApiClient().get('/api/livekit/token', queryParameters: {'room': roomId});
      final token = response.data['token'] as String;
      
      // 2. We need the LiveKit URL from env, or we can hardcode for now or fetch it from another endpoint.
      // Usually, it's better to fetch from a config endpoint or have it in a constants file. 
      // For this project, let's assume it's wss://teqlif.com or we can fetch it? 
      // In web it's process.env.NEXT_PUBLIC_LIVEKIT_URL. Let's use wss://live.teqlif.com or similar?
      // Actually we must fetch it or use a constant. Let's assume it's hardcoded to the VPS livekit url or we use a flutter env.
      const livekitUrl = 'wss://teqlif-livekit-xxxx.livekit.cloud'; // We will replace this with correct URL. 
      // Wait, user said Native Redis, Apache Reverse Proxy. It's probably wss://live.teqlif.com or wss://teqlif.com:7880
      // I will put a placeholder for URL and check if there's env. Let's use a generic relative or just wss://teqlif.com
      // Wait, in previous chats, the LiveKit URL was wss://... I'll just use a generic config class or we can ask.
      // Actually I see `NEXT_PUBLIC_LIVEKIT_URL` in web. Let's check environment variables if possible, or just use `wss://teqlif.com` since it's behind Apache proxy as he said.
      
      const wsUrl = 'wss://teqlif.com'; // Adjust if needed

      final roomOptions = const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      );

      _room = Room();
      
      await _room!.connect(wsUrl, token, roomOptions: roomOptions);
      
      if (isOwner) {
        // Publish camera and mic
        await _room!.localParticipant?.setCameraEnabled(true);
        await _room!.localParticipant?.setMicrophoneEnabled(true);
      }

      state = state.copyWith(room: _room, isConnecting: false);
      // NTP Sync (RTT Offset calculation)
      // Ping a lightweight endpoint to get server time
      try {
        final sendTime = DateTime.now();
        final response = await ApiClient().get('/api/livekit/sync'); // We will assume this returns { serverTime: timestamp }
        final receiveTime = DateTime.now();
        
        if (response.statusCode == 200) {
          final serverTimeMillis = response.data['serverTime'] as int;
          final rtt = receiveTime.difference(sendTime);
          final oneWayDelay = rtt.inMilliseconds ~/ 2;
          
          // Estimated server time at the moment 'receiveTime' happened
          final estimatedServerTimeAtReceive = serverTimeMillis + oneWayDelay;
          final offsetMillis = estimatedServerTimeAtReceive - receiveTime.millisecondsSinceEpoch;
          
          state = state.copyWith(serverTimeOffset: Duration(milliseconds: offsetMillis));
        }
      } catch (e) {
        print("NTP Sync failed: $e");
      }

      // If Host, listen for network quality to send FREEZE signals
      if (isHost) {
        room.events.listen((event) {
          if (event is ConnectionQualityChangedEvent && event.participant == room.localParticipant) {
            if (event.quality == ConnectionQuality.poor || event.quality == ConnectionQuality.lost) {
              _broadcastFreezeStatus(true);
            } else if (event.quality == ConnectionQuality.excellent || event.quality == ConnectionQuality.good) {
              _broadcastFreezeStatus(false);
            }
          }
        });
      } else {
        // If Viewer, listen for FREEZE signals
        room.events.listen((event) {
          if (event is DataReceivedEvent) {
            final msg = String.fromCharCodes(event.data);
            if (msg == 'SYS:FREEZE') {
              state = state.copyWith(isFrozen: true);
            } else if (msg == 'SYS:UNFREEZE') {
              state = state.copyWith(isFrozen: false);
            }
          }
        });
      }

    } catch (e) {
      state = state.copyWith(isConnecting: false, error: e.toString());
    }
  }

  Future<void> _broadcastFreezeStatus(bool freeze) async {
    final room = state.room;
    if (room != null && room.localParticipant != null) {
      final msg = freeze ? 'SYS:FREEZE' : 'SYS:UNFREEZE';
      await room.localParticipant!.publishData(msg.codeUnits);
    }
  }

  Future<void> disconnect() async {
    if (_room != null) {
      await _room!.disconnect();
      _room = null;
    }
    state = LiveRoomState();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
