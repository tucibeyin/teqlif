abstract final class MediaConstants {
  static const int imageMaxBytes = 5 * 1024 * 1024;   // 5 MB
  static const int videoMaxBytes = 20 * 1024 * 1024;  // 20 MB
  static const int voiceMaxBytes = 512 * 1024;          // 512 KB
  static const int fileMaxBytes  = 5 * 1024 * 1024;   // 5 MB

  static const int videoMaxSecs = 15;
  static const int voiceMaxSecs = 30;

  static const Set<String> allowedFileExtensions = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt',
  };
}
