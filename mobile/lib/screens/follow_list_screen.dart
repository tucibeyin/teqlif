import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/theme.dart';
import '../services/storage_service.dart';
import 'public_profile_screen.dart';

enum FollowListType { followers, following }

class FollowListScreen extends StatefulWidget {
  final int userId;
  final FollowListType type;
  final String title;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.type,
    required this.title,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    final segment = widget.type == FollowListType.followers ? 'followers' : 'following';
    try {
      final headers = await _authHeaders();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/follows/${widget.userId}/$segment'),
        headers: headers,
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _users = jsonDecode(resp.body) as List;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow(int index) async {
    final user = Map<String, dynamic>.from(_users[index] as Map);
    final isFollowing = user['is_following'] as bool;
    final userId = user['id'] as int;

    // Optimistic update
    setState(() {
      _users[index] = {...user, 'is_following': !isFollowing};
    });

    try {
      final headers = await _authHeaders();
      final uri = Uri.parse('$kBaseUrl/follows/$userId');
      final resp = isFollowing
          ? await http.delete(uri, headers: headers)
          : await http.post(uri, headers: headers);
      if (resp.statusCode >= 400 && mounted) {
        // Revert on error
        setState(() {
          _users[index] = {...user, 'is_following': isFollowing};
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _users[index] = {...user, 'is_following': isFollowing};
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_outline, size: 56, color: Color(0xFFD1D5DB)),
                      const SizedBox(height: 12),
                      Text(
                        widget.type == FollowListType.followers
                            ? 'Henüz takipçi yok'
                            : 'Henüz takip edilen yok',
                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (ctx, i) {
                    final u = _users[i] as Map<String, dynamic>;
                    final isMe = u['is_me'] as bool? ?? false;
                    final isFollowing = u['is_following'] as bool? ?? false;
                    final fullName = u['full_name'] as String? ?? '';
                    final username = u['username'] as String? ?? '';
                    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PublicProfileScreen(username: username),
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: kPrimary.withOpacity(0.12),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      title: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PublicProfileScreen(username: username),
                          ),
                        ),
                        child: Text(
                          fullName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      subtitle: Text(
                        '@$username',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      ),
                      trailing: isMe
                          ? null
                          : SizedBox(
                              width: 100,
                              child: OutlinedButton(
                                onPressed: () => _toggleFollow(i),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isFollowing ? null : kPrimary,
                                  foregroundColor: isFollowing ? const Color(0xFF374151) : Colors.white,
                                  side: BorderSide(
                                    color: isFollowing ? const Color(0xFFD1D5DB) : kPrimary,
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: Text(isFollowing ? 'Takiptesin' : 'Takip Et'),
                              ),
                            ),
                    );
                  },
                ),
    );
  }
}
