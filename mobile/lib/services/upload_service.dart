import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import 'storage_service.dart';

/// Upload sonucu: orijinal URL ve thumbnail URL.
typedef UploadResult = ({String url, String? thumbUrl});

class UploadService {
  /// Bir dosyayı backend'e yükler.
  /// Başarı durumunda [UploadResult] döner; hata durumunda [Exception] fırlatır.
  static Future<UploadResult> uploadFile(File file) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('Oturum açık değil');

    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload'));
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      String detail = body;
      try {
        detail = (jsonDecode(body) as Map)['detail']?.toString() ?? body;
      } catch (_) {}
      throw Exception('Yükleme başarısız: $detail');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return (
      url: json['url'] as String,
      thumbUrl: json['thumb_url'] as String?,
    );
  }
}
