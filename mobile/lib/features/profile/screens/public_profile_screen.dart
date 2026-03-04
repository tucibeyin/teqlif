import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/providers/user_provider.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/endpoints.dart';
import '../../../../core/models/ad.dart';

class PublicProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const PublicProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _isLoading = true;
  bool _isActionLoading = false;
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final data = await ref.read(userProvider.notifier).fetchUserProfile(widget.userId);
    if (mounted) {
      if (data != null) {
        setState(() {
          _profileData = data;
          _isLoading = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı profili yüklenemedi')),
        );
        context.pop();
      }
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _isActionLoading = true);
    
    final connectionStatus = _profileData!['connectionStatus'] as String;
    bool success = false;

    if (connectionStatus == 'FRIEND') {
      success = await ref.read(userProvider.notifier).unfollowUser(widget.userId);
      if (success && mounted) {
        setState(() => _profileData!['connectionStatus'] = 'NONE');
      }
    } else {
      success = await ref.read(userProvider.notifier).followUser(widget.userId);
      if (success && mounted) {
        setState(() => _profileData!['connectionStatus'] = 'FRIEND');
      }
    }

    setState(() => _isActionLoading = false);
  }

  Future<void> _sendMessage() async {
    setState(() => _isActionLoading = true);
    try {
      final res = await ApiClient().post(Endpoints.conversations, data: {
        'userId': widget.userId,
      });
      final conversationId = res.data['id'];
      if (mounted) {
        context.push('/messages/$conversationId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sohbet başlatılamadı.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _assignUserToList() async {
    if (ref.read(userProvider).lists.isEmpty) {
      await ref.read(userProvider.notifier).fetchFriendsData();
    }
    if (!mounted) return;
    final lists = ref.read(userProvider).lists;
    final user = _profileData!['user'] as PublicUserProfile;
    
    final newSelectedListId = await showModalBottomSheet<String?>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('${user.name} için Liste Seçin', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              title: const Text('⭐ Listesiz (Varsayılan)'),
              onTap: () => Navigator.pop(context, 'null'),
            ),
            const Divider(height: 1),
            ...lists.map((l) => ListTile(
              title: Text(l.name),
              onTap: () => Navigator.pop(context, l.id),
            )),
          ],
        ),
      )
    );

    if (newSelectedListId != null) {
      final idToSet = newSelectedListId == 'null' ? null : newSelectedListId;
      await ref.read(userProvider.notifier).assignFriendToList(widget.userId, idToSet);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Liste güncellendi.')));
      }
    }
  }

  Future<void> _handleBlockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Engelle'),
        content: const Text('Bu kullanıcıyı engellemek istediğinize emin misiniz? Birbirinizin ilanlarını ve mesajlarını göremezsiniz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Engelle', style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );

    if (confirm != true) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient().post(Endpoints.blockUser, data: {'targetUserId': widget.userId});
      if (mounted) {
        setState(() => _profileData!['connectionStatus'] = 'BLOCKED_BY_ME');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanıcı engellendi.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleUnblockUser() async {
    setState(() => _isActionLoading = true);
    try {
      await ApiClient().delete(Endpoints.blockUser, params: {'userId': widget.userId});
      if (mounted) {
        setState(() => _profileData!['connectionStatus'] = 'NONE');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanıcının engeli kaldırıldı.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleReportUser() async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Şikayet Et'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Şikayet nedeninizi yazınız...', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Şikayet Et', style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );

    if (confirm != true || reasonController.text.trim().isEmpty) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient().post(Endpoints.report, data: {
        'reportedId': widget.userId,
        'reason': reasonController.text.trim()
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Şikayetiniz alındı.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Şikayet gönderilemedi.')));
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = _profileData!['user'] as PublicUserProfile;
    final ads = _profileData!['ads'] as List<AdModel>;
    final connectionStatus = _profileData!['connectionStatus'] as String;

    final joinedDate = DateFormat.yMMMM('tr_TR').format(DateTime.parse(user.joinedAt));

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(user.name),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        actions: connectionStatus != 'SELF' ? [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') _handleBlockUser();
              if (value == 'unblock') _handleUnblockUser();
              if (value == 'report') _handleReportUser();
            },
            itemBuilder: (context) => [
              if (connectionStatus == 'BLOCKED_BY_ME')
                const PopupMenuItem(value: 'unblock', child: Text('Engeli Kaldır'))
              else
                const PopupMenuItem(value: 'block', child: Text('Kullanıcıyı Engelle', style: TextStyle(color: Colors.red))),
              const PopupMenuItem(value: 'report', child: Text('Şikayet Et', style: TextStyle(color: Colors.red))),
            ]
          )
        ] : null,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24.0),
              width: double.infinity,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    backgroundImage: user.avatar != null ? NetworkImage(imageUrl(user.avatar)) : null,
                    child: user.avatar == null
                        ? Text(user.name[0].toUpperCase(), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor))
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'teqlif Üyesi • $joinedDate',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  if (user.phone != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(user.phone!, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  
                  const SizedBox(height: 24),
                  
                  if (connectionStatus == 'BLOCKED_BY_THEM')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[200]!)
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.block, color: Colors.red, size: 48),
                          SizedBox(height: 12),
                          Text('Bu profile erişemezsiniz.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                        ]
                      ),
                    )
                  else if (connectionStatus == 'BLOCKED_BY_ME')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[200]!)
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.person_off, color: Colors.orange, size: 48),
                          SizedBox(height: 12),
                          Text('Bu kullanıcıyı engellediniz.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
                          Text('Engeli kaldırarak profili görüntüleyebilirsiniz.', textAlign: TextAlign.center, style: TextStyle(color: Colors.orange)),
                        ]
                      ),
                    )
                  else ...[
                    // Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStatItem('Aktif İlan', user.stats['activeAds'].toString()),
                        Container(width: 1, height: 40, color: Colors.grey[300], margin: const EdgeInsets.symmetric(horizontal: 24)),
                        _buildStatItem('Takipçi', user.stats['followers'].toString()),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Actions
                    if (connectionStatus != 'SELF')
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isActionLoading ? null : _toggleFollow,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: connectionStatus == 'FRIEND' ? Colors.grey[200] : Theme.of(context).primaryColor,
                                  foregroundColor: connectionStatus == 'FRIEND' ? Colors.black87 : Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  elevation: connectionStatus == 'FRIEND' ? 0 : 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _isActionLoading
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(connectionStatus == 'FRIEND' ? 'Takipten Çık' : 'Takip Et', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _sendMessage,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(context).primaryColor,
                                  side: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Mesaj Gönder', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                        if (connectionStatus == 'FRIEND') ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _assignUserToList,
                              icon: const Icon(Icons.list),
                              label: const Text('Listeye Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                                side: BorderSide(color: Colors.grey[300]!, width: 2),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                        ],
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (connectionStatus != 'BLOCKED_BY_THEM' && connectionStatus != 'BLOCKED_BY_ME')
              // Ads Grid
              Container(
              padding: const EdgeInsets.all(16.0),
              width: double.infinity,
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Kullanıcının İlanları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (ads.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text('Aktif ilan bulunmuyor', style: TextStyle(color: Colors.grey[500])),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: ads.length,
                      itemBuilder: (context, index) {
                        final ad = ads[index];
                        final formatCurrency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
                        
                        return GestureDetector(
                          onTap: () => context.push('/ad/${ad.id}'),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ad.images.isNotEmpty
                                          ? Image.network(imageUrl(ad.images.first), fit: BoxFit.cover)
                                          : Container(color: Colors.grey[200], child: const Icon(Icons.image, color: Colors.grey)),
                                      if (ad.isAuction)
                                        Positioned(
                                          top: 8, right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
                                            child: const Text('Açık Arttırma', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(ad.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                        Text(formatCurrency.format(ad.price), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
      ],
    );
  }
}
