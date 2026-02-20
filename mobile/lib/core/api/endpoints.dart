const String kBaseUrl = 'https://teqlif.com';

class Endpoints {
  // Auth
  static const login = '/api/auth/mobile';
  static const register = '/api/auth/register';
  static const pushRegister = '/api/push/register';

  // Ads
  static const ads = '/api/ads';
  static String adById(String id) => '/api/ads/$id';
  static String republishAd(String id) => '/api/ads/$id/republish';
  static const search = '/api/search';

  // Bids
  static const bids = '/api/bids';
  static String acceptBid(String id) => '/api/bids/$id/accept';
  static String cancelBid(String id) => '/api/bids/$id/cancel';

  // Conversations & Messages
  static const conversations = '/api/conversations';
  static const messages = '/api/messages';
  static const messagesUnread = '/api/messages/unread';

  // Notifications
  static const notifications = '/api/notifications';

  // Upload
  static const upload = '/api/upload';
}
