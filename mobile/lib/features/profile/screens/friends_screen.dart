import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/user_provider.dart';
import '../../../../core/api/endpoints.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  String? _selectedListId;

  @override
  void initState() {
    super.initState();
    // Fetch fresh data when screen opens
    Future.microtask(() => ref.read(userProvider.notifier).fetchFriendsData());
  }

  Future<void> _createList() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Liste Oluştur', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Liste Adı (Örn: Güvenilirler)',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final success = await ref.read(userProvider.notifier).createFriendList(result);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Liste oluşturulamadı.')));
      }
    }
  }

  Future<void> _deleteList(String listId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Listeyi Sil'),
        content: const Text('Bu listeyi silmek istediğinize emin misiniz? (İçindeki kişiler takipten çıkmaz, sadece listesiz kalırlar)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Evet, Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(userProvider.notifier).deleteFriendList(listId);
      if (_selectedListId == listId) {
        setState(() => _selectedListId = null);
      }
    }
  }

  Future<void> _assignUserToList(Friend friend) async {
    final lists = ref.read(userProvider).lists;
    
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
              child: Text('${friend.name} için Liste Seçin', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              title: const Text('⭐ Listesiz (Varsayılan)'),
              trailing: friend.friendListId == null ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
              onTap: () => Navigator.pop(context, 'null'),
            ),
            const Divider(height: 1),
            ...lists.map((l) => ListTile(
              title: Text(l.name),
              trailing: friend.friendListId == l.id ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
              onTap: () => Navigator.pop(context, l.id),
            )),
          ],
        ),
      )
    );

    if (newSelectedListId != null) {
      final idToSet = newSelectedListId == 'null' ? null : newSelectedListId;
      await ref.read(userProvider.notifier).assignFriendToList(friend.id, idToSet);
    }
  }

  Future<void> _unfollow(Friend friend) async {
     final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Takipten Çıkar'),
        content: Text('${friend.name} kişisini takipten çıkarmak istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Takipten Çıkar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(userProvider.notifier).unfollowUser(friend.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(userProvider);
    final displayedFriends = _selectedListId == null 
        ? provider.friends 
        : provider.friends.where((f) => f.friendListId == _selectedListId).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arkadaşlarım'),
        centerTitle: true,
      ),
      backgroundColor: Colors.grey[50],
      body: provider.isLoadingFriends && provider.friends.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              // Horizontal List Selector
              Container(
                height: 60,
                color: Colors.white,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  children: [
                    _buildListChip(
                      label: 'Tümü (${provider.friends.length})',
                      isSelected: _selectedListId == null,
                      onTap: () => setState(() => _selectedListId = null),
                    ),
                    const SizedBox(width: 8),
                    ...provider.lists.map((l) {
                      final count = provider.friends.where((f) => f.friendListId == l.id).length;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: _buildListChip(
                          label: '${l.name} ($count)',
                          isSelected: _selectedListId == l.id,
                          onTap: () => setState(() => _selectedListId = l.id),
                          onLongPress: () => _deleteList(l.id),
                        ),
                      );
                    }),
                    const SizedBox(width: 4),
                    ActionChip(
                      label: const Text('+ Yeni', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      backgroundColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide.none,
                      onPressed: _createList,
                    )
                  ],
                ),
              ),
              const Divider(height: 1),

              // Friends Grid
              Expanded(
                child: displayedFriends.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              _selectedListId == null ? 'Henüz kimseyi takip etmiyorsunuz' : 'Bu listede kimse yok',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.read(userProvider.notifier).fetchFriendsData(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: displayedFriends.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final friend = displayedFriends[index];
                            final listName = friend.friendListId == null 
                                ? 'Listesiz' 
                                : provider.lists.firstWhere((l) => l.id == friend.friendListId, orElse: () => FriendList(id: '', name: 'Bilinmeyen')).name;
                            
                            return InkWell(
                              onTap: () => context.push('/user/${friend.id}'),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey[200]!),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    )
                                  ]
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                      backgroundImage: friend.avatar != null ? NetworkImage(imageUrl(friend.avatar)) : null,
                                      child: friend.avatar == null ? Text(friend.name[0].toUpperCase(), style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 20)) : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(friend.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          const SizedBox(height: 4),
                                          GestureDetector(
                                            onTap: () => _assignUserToList(friend),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[100],
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(friend.friendListId == null ? Icons.star_border : Icons.list, size: 12, color: Colors.grey[600]),
                                                  const SizedBox(width: 4),
                                                  Text(listName, style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                                                  const SizedBox(width: 4),
                                                  const Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chat_bubble_outline),
                                      color: Theme.of(context).primaryColor,
                                      onPressed: () {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mesaj gönderme başlatılacak.')));
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.person_remove_outlined),
                                      color: Colors.red[300],
                                      onPressed: () => _unfollow(friend),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
    );
  }

  Widget _buildListChip({required String label, required bool isSelected, required VoidCallback onTap, VoidCallback? onLongPress}) {
    return ActionChip(
      label: Text(label, style: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      )),
      backgroundColor: isSelected ? Theme.of(context).primaryColor : Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide.none,
      onPressed: onTap,
      onLongPress: onLongPress,
    );
  }
}
