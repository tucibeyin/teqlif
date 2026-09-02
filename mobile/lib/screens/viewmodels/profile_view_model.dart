import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/wallet_service.dart';
import '../../core/logger_service.dart';
import '../../models/listing_filter_state.dart';

class ProfileUiState {
  final Map<String, dynamic>? user;
  final List<dynamic> listings;
  final bool loading;
  final bool listingsError;
  final bool purchasesLoading;
  final int? tuciBalance;
  final List<dynamic> tuciHistory;
  final ListingFilterState filter;

  final bool showPrivacyBanner;

  const ProfileUiState({
    this.user,
    this.listings = const [],
    this.loading = true,
    this.listingsError = false,
    this.purchasesLoading = false,
    this.tuciBalance,
    this.tuciHistory = const [],
    this.filter = const ListingFilterState(),
    this.showPrivacyBanner = false,
  });

  ProfileUiState copyWith({
    Map<String, dynamic>? user,
    List<dynamic>? listings,
    bool? loading,
    bool? listingsError,
    bool? purchasesLoading,
    int? tuciBalance,
    List<dynamic>? tuciHistory,
    ListingFilterState? filter,
    bool? showPrivacyBanner,
  }) {
    return ProfileUiState(
      user: user ?? this.user,
      listings: listings ?? this.listings,
      loading: loading ?? this.loading,
      listingsError: listingsError ?? this.listingsError,
      purchasesLoading: purchasesLoading ?? this.purchasesLoading,
      tuciBalance: tuciBalance ?? this.tuciBalance,
      tuciHistory: tuciHistory ?? this.tuciHistory,
      filter: filter ?? this.filter,
      showPrivacyBanner: showPrivacyBanner ?? this.showPrivacyBanner,
    );
  }

  List<dynamic> get filteredListings {
    var r = listings;
    if (filter.category != null && filter.category!.isNotEmpty) {
      r = r.where((l) => l['category'] == filter.category).toList();
    }
    if (filter.subcategory != null && filter.subcategory!.isNotEmpty) {
      r = r.where((l) => l['subcategory'] == filter.subcategory).toList();
    }
    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      final q = filter.searchQuery!.toLowerCase();
      r = r.where((l) {
        final title = (l['title'] as String? ?? '').toLowerCase();
        final desc = (l['description'] as String? ?? '').toLowerCase();
        return title.contains(q) || desc.contains(q);
      }).toList();
    }
    if (filter.dateFrom != null && filter.dateTo != null) {
      final start = filter.dateFrom!;
      final end = filter.dateTo!.add(const Duration(days: 1));
      r = r.where((l) {
        final dateStr = l['created_at'] as String?;
        if (dateStr == null) return true;
        final date = DateTime.tryParse(dateStr);
        if (date == null) return true;
        return !date.isBefore(start) && date.isBefore(end);
      }).toList();
    }
    return r;
  }
}

class ProfileViewModel extends AutoDisposeAsyncNotifier<ProfileUiState> {
  StreamSubscription? _profileSub;
  StreamSubscription? _listingsSub;
  StreamSubscription? _walletSub;

  @override
  FutureOr<ProfileUiState> build() async {
    final localInfo = await StorageService.getUserInfo();
    
    Future.microtask(() => load());

    if (localInfo != null) {
      final avatarUrl = StorageService.cachedAvatarUrl;
      if (avatarUrl != null) localInfo['profile_image_url'] = avatarUrl;
    }

    ref.onDispose(() {
      _profileSub?.cancel();
      _listingsSub?.cancel();
      _walletSub?.cancel();
    });

    return ProfileUiState(
      user: localInfo,
      loading: true,
    );
  }

  void updateFilter(ListingFilterState filter) {
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(filter: filter));
    }
  }

  Future<void> loadPurchases() async {
    if (!state.hasValue || state.value!.purchasesLoading) return;
    state = AsyncValue.data(state.value!.copyWith(purchasesLoading: true));
    try {
      final token = await StorageService.getToken();
      if (token != null) {
        await http.get(
          Uri.parse('$kBaseUrl/auth/me/purchases'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
    } catch (_) {
      // silent
    } finally {
      if (state.hasValue) {
        state = AsyncValue.data(state.value!.copyWith(purchasesLoading: false));
      }
    }
  }

  Future<void> loadWallet({bool bypassCache = false}) async {
    _walletSub?.cancel();
    _walletSub = WalletService.getBalanceStream(bypassCache: bypassCache).listen((wallet) {
      if (state.hasValue) {
        state = AsyncValue.data(state.value!.copyWith(
          tuciBalance: wallet['balance'] as int?,
          tuciHistory: wallet['transactions'] as List? ?? [],
        ));
      }
    });
  }

  Future<void> load({bool bypassCache = false}) async {
    _profileSub?.cancel();
    _listingsSub?.cancel();
    _walletSub?.cancel();

    final localInfo = await StorageService.getUserInfo();
    final username = localInfo?['username'] as String?;
    final userId = localInfo?['id'] as int?;

    if (username == null || userId == null) {
      if (state.hasValue) {
        state = AsyncValue.data(state.value!.copyWith(loading: false));
      }
      return;
    }

    _profileSub = ApiService.get<Map<String, dynamic>>(
      url: '$kBaseUrl/users/$username',
      cacheKey: StorageService.cacheProfile,
      cacheTtl: const Duration(minutes: 10),
      bypassCache: bypassCache,
      fromJson: (raw) => Map<String, dynamic>.from(raw as Map),
    ).listen(
      (user) async {
        final avatarUrl = user['profile_image_url'] as String?;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          StorageService.saveAvatarUrl(avatarUrl);
        }

        StorageService.saveUserInfo(
          id: user['id'] as int? ?? userId,
          email: localInfo?['email'] as String? ?? '',
          username: user['username'] as String? ?? username,
          fullName: user['full_name'] as String? ?? '',
          isPremium: user['is_premium'] == true,
          onboardingCompleted: user['onboarding_completed'] == true,
          isVerified: user['is_verified'] == true,
          phoneVerified: user['phone_verified'] == true,
        );

        final isPrivate = user['is_private'] == true;
        final bannerShown = await StorageService.getPrivacyBannerShown();

        if (state.hasValue) {
          state = AsyncValue.data(state.value!.copyWith(
            user: user,
            loading: false,
            showPrivacyBanner: !isPrivate && !bannerShown,
          ));
        }
      },
      onError: (e) {
        LoggerService.instance.warning('ProfileViewModel', 'Profil yüklenemedi: $e');
        if (state.hasValue) {
          state = AsyncValue.data(state.value!.copyWith(loading: false));
        }
      },
    );

    _listingsSub = ApiService.get<List<dynamic>>(
      url: '$kBaseUrl/listings/my?limit=1000',
      cacheKey: StorageService.cacheUserListings,
      cacheTtl: const Duration(minutes: 5),
      bypassCache: bypassCache,
      fromJson: (raw) => raw as List,
    ).listen(
      (listings) {
        if (state.hasValue) {
          state = AsyncValue.data(state.value!.copyWith(
            listings: listings,
            loading: false,
            listingsError: false,
          ));
        }
      },
      onError: (_) {
        if (state.hasValue) {
          state = AsyncValue.data(state.value!.copyWith(
            loading: false,
            listingsError: true,
          ));
        }
      },
    );

    loadPurchases();
    loadWallet(bypassCache: bypassCache);
  }

  Future<void> dismissPrivacyBanner() async {
    await StorageService.setPrivacyBannerShown(true);
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(showPrivacyBanner: false));
    }
  }
}

final profileViewModelProvider = AutoDisposeAsyncNotifierProvider<ProfileViewModel, ProfileUiState>(
  () => ProfileViewModel(),
);
