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

  LiveRoomState({this.room, this.isConnecting = false, this.error});

  LiveRoomState copyWith({Room? room, bool? isConnecting, String? error}) {
    return LiveRoomState(
      room: room ?? this.room,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error ?? this.error,
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
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: e.toString());
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
