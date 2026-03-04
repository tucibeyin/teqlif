import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../models/ad.dart';

class PublicUserProfile {
  final String id;
  final String name;
  final String? avatar;
  final String joinedAt;
  final String? phone;
  final Map<String, dynamic> stats;

  PublicUserProfile({
    required this.id,
    required this.name,
    this.avatar,
    required this.joinedAt,
    this.phone,
    required this.stats,
  });

  factory PublicUserProfile.fromJson(Map<String, dynamic> json) {
    return PublicUserProfile(
      id: json['id'],
      name: json['name'],
      avatar: json['avatar'],
      joinedAt: json['createdAt'],
      phone: json['phone'],
      stats: json['stats'] ?? {'activeAds': 0, 'followers': 0},
    );
  }
}

class FriendList {
  final String id;
  final String name;

  FriendList({required this.id, required this.name});

  factory FriendList.fromJson(Map<String, dynamic> json) {
    return FriendList(
      id: json['id'],
      name: json['name'],
    );
  }
}

class Friend {
  final String id;
  final String name;
  final String? avatar;
  final String? friendListId;

  Friend({
    required this.id,
    required this.name,
    this.avatar,
    this.friendListId,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: json['id'],
      name: json['name'],
      avatar: json['avatar'],
      friendListId: json['friendListId'],
    );
  }
}

class UserProvider with ChangeNotifier {
  final ApiClient _api = ApiClient();

  List<Friend> _friends = [];
  List<FriendList> _lists = [];
  bool _isLoadingFriends = false;

  List<Friend> get friends => _friends;
  List<FriendList> get lists => _lists;
  bool get isLoadingFriends => _isLoadingFriends;

  // ==== Public Profile ====

  Future<Map<String, dynamic>?> fetchUserProfile(String userId) async {
    try {
      final res = await _api.get(Endpoints.userById(userId));
      if (res.statusCode == 200) {
        final data = res.data;
        final user = PublicUserProfile.fromJson(data['user']);
        final ads = (data['ads'] as List).map((ad) => AdModel.fromJson(ad)).toList();
        final connectionStatus = data['connectionStatus'] as String;
        return {
          'user': user,
          'ads': ads,
          'connectionStatus': connectionStatus,
        };
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
    return null;
  }

  // ==== Friends Management ====

  Future<void> fetchFriendsData() async {
    _isLoadingFriends = true;
    notifyListeners();

    try {
      final res = await _api.get(Endpoints.friends);
      if (res.statusCode == 200) {
        final data = res.data;
        _friends = (data['friends'] as List?)?.map((f) => Friend.fromJson(f)).toList() ?? [];
        _lists = (data['customLists'] as List?)?.map((l) => FriendList.fromJson(l)).toList() ?? [];
      }
    } catch (e) {
      debugPrint('Error fetching friends: $e');
    } finally {
      _isLoadingFriends = false;
      notifyListeners();
    }
  }

  Future<bool> followUser(String userId) async {
    try {
      final res = await _api.post(Endpoints.friends, data: {'targetUserId': userId});
      if (res.statusCode == 200 || res.statusCode == 201) {
        fetchFriendsData(); // Refresh list silently
        return true;
      }
    } catch (e) {
      debugPrint('Error following user: $e');
    }
    return false;
  }

  Future<bool> unfollowUser(String userId) async {
    try {
      final res = await _api.delete(Endpoints.friendById(userId));
      if (res.statusCode == 200) {
        // Optimistically remove
        _friends.removeWhere((f) => f.id == userId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error unfollowing user: $e');
    }
    return false;
  }

  // ==== List Management ====

  Future<bool> createFriendList(String name) async {
    try {
      final res = await _api.post(Endpoints.friendLists, data: {'name': name});
      if (res.statusCode == 200 || res.statusCode == 201) {
        final list = FriendList.fromJson(res.data['list']);
        _lists.add(list);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error creating friend list: $e');
    }
    return false;
  }

  Future<bool> deleteFriendList(String listId) async {
    try {
      final res = await _api.delete(Endpoints.friendListById(listId));
      if (res.statusCode == 200) {
        _lists.removeWhere((l) => l.id == listId);
        // Clear references
        for (var i = 0; i < _friends.length; i++) {
          if (_friends[i].friendListId == listId) {
             _friends[i] = Friend(
              id: _friends[i].id,
              name: _friends[i].name,
              avatar: _friends[i].avatar,
              friendListId: null,
            );
          }
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting friend list: $e');
    }
    return false;
  }

  Future<bool> assignFriendToList(String friendId, String? listId) async {
    try {
      final targetUrl = listId == null 
        ? Endpoints.friendListMembers('null') 
        : Endpoints.friendListMembers(listId);
      final res = await _api.patch(targetUrl, data: {'friendId': friendId});

      if (res.statusCode == 200) {
        // Optimistic update
        final int index = _friends.indexWhere((f) => f.id == friendId);
        if (index != -1) {
          _friends[index] = Friend(
            id: _friends[index].id,
            name: _friends[index].name,
            avatar: _friends[index].avatar,
            friendListId: listId,
          );
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error assigning friend to list: $e');
    }
    return false;
  }
}

final userProvider = ChangeNotifierProvider<UserProvider>((ref) => UserProvider());
