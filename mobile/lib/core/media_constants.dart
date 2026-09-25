abstract final class MediaConstants {
  static const int imageMaxBytes        = 3 * 1024 * 1024;   // 3 MB
  static const int videoMaxBytes        = 20 * 1024 * 1024;  // 20 MB (DM video)
  static const int listingVideoMaxBytes = 50 * 1024 * 1024;  // 50 MB (İlan video — client sıkıştırır)
  static const int voiceMaxBytes        = 2 * 1024 * 1024;   // 2 MB  (Opus 16kbps 10 dk)
  static const int fileMaxBytes         = 50 * 1024 * 1024;  // 50 MB

  static const int videoMaxSecs        = 90;   // DM video
  static const int listingVideoMaxSecs = 60;   // İlan videosu
  static const int voiceMaxSecs        = 600;  // 10 dakika

  static const Set<String> allowedFileExtensions = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt',
  };
}
