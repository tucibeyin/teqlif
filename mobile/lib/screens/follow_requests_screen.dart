import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../config/api.dart';
import '../services/storage_service.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import 'public_profile_screen.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  List<dynamic> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/follows/requests'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        setState(() {
          _requests = jsonDecode(resp.body) as List;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'error_load';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'error_network';
        _loading = false;
      });
    }
  }

  Future<void> _handleAction(int followerId, String action) async {
    try {
      final token = await StorageService.getToken();
      final uri = Uri.parse('$kBaseUrl/follows/$followerId/$action');
      debugPrint('[FollowRequests] Action: $action on follower_id: $followerId | URI: $uri');
      
      final resp = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      
      debugPrint('[FollowRequests] Response status: ${resp.statusCode} body: ${resp.body}');
      
      if (resp.statusCode == 200) {
        setState(() {
          _requests.removeWhere((req) => req['id'] == followerId);
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.errorGenericRetry)),
          );
        }
      }
    } catch (e) {
      debugPrint('[FollowRequests] Network error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errNetworkRetry)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.followRequests),
        centerTitle: true,
      ),
      backgroundColor: AppColors.bg(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error == 'error_load' ? l.errorFollowRequestsLoad : l.errNetworkRetry))
              : _requests.isEmpty
                  ? Center(
                      child: Text(
                        l.noFollowRequests,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _requests.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final user = _requests[index];
                        final String username = user['username'];
                        final String fullName = user['full_name'];
                        final String? avatarUrl = user['profile_image_thumb_url'];

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(username: username),
                              ),
                            ).then((_) => _loadRequests()),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.surfaceVariant(context),
                              backgroundImage: avatarUrl != null
                                  ? CachedNetworkImageProvider(imgUrl(avatarUrl))
                                  : null,
                              child: avatarUrl == null
                                  ? Text(
                                      fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: AppColors.textPrimary(context),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          title: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(username: username),
                              ),
                            ).then((_) => _loadRequests()),
                            child: Text(
                              username,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                          subtitle: Text(
                            fullName,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 13,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _handleAction(user['id'], 'accept'),
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                                child: Text(l.acceptRequest, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => _handleAction(user['id'], 'reject'),
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColors.surfaceVariant(context),
                                  foregroundColor: AppColors.textPrimary(context),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                                child: Text(l.rejectRequest, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
