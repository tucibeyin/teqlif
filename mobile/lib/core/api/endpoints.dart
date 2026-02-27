const String kBaseUrl = 'https://teqlif.com';

/// Returns a full URL for an image path.
/// Handles both already-absolute URLs (http/https) and relative paths (/uploads/...).
String imageUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '$kBaseUrl$path';
}

class Endpoints {
  // Auth
  static const login = '/api/mobile/login';
  static const register = '/api/auth/register';
  static const pushRegister = '/api/push/register';
  static const pushUnregister = '/api/push/unregister';
  static const verifyEmail = '/api/auth/verify-email';
  static const forgotPassword = '/api/auth/forgot-password';
  static const resetPassword = '/api/auth/reset-password';

  // Ads
  static const ads = '/api/ads';
  static String adById(String id) => '/api/ads/$id';
  static String republishAd(String id) => '/api/ads/$id/republish';
  static const search = '/api/search';

  // Bids
  static const bids = '/api/bids';
  static String acceptBid(String id) => '/api/bids/$id/accept';
  static String cancelBid(String id) => '/api/bids/$id/cancel';

  // Favorites
  static const favorites = '/api/favorites';
  static String favoriteById(String id) => '/api/favorites/$id';

  // Conversations & Messages
  static const conversations = '/api/conversations';
  static const messages = '/api/messages';
  static const messagesUnread = '/api/messages/unread';

  // Notifications
  static const notifications = '/api/notifications';

  // Upload
  static const upload = '/api/upload';
}
