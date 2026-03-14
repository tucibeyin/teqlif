import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/api.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'messages_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  final String username;
  final int? userId;

  const PublicProfileScreen({
    super.key,
    required this.username,
    this.userId,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _isOwnProfile = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await NotificationService.getUserByUsername(widget.username);
    final info = await StorageService.getUserInfo();
    if (mounted) {
      setState(() {
        _user = data;
        _isOwnProfile = info != null && info['username'] == widget.username;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _user == null
              ? const Center(child: Text('Kullanıcı bulunamadı'))
              : _buildProfile(),
    );
  }

  Widget _buildProfile() {
    final fullName = _user!['full_name'] as String? ?? widget.username;
    final userId = (_user!['id'] as int?) ?? widget.userId ?? 0;
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 44,
            backgroundColor: kPrimary.withOpacity(0.15),
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: kPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fullName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '@${widget.username}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 32),
          if (!_isOwnProfile && userId != 0)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Mesaj Gönder'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DirectChatScreen(
                        otherUserId: userId,
                        displayName: fullName,
                        otherHandle: widget.username,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
