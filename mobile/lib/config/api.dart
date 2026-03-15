const String kBaseUrl = 'https://teqlif.com/api';
const String kBaseHost = 'https://teqlif.com';

/// /uploads/... → https://teqlif.com/uploads/...
String imgUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  return '$kBaseHost$path';
}
