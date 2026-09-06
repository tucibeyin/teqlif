import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global medya sıkıştırma progress state'i.
/// null  = sıkıştırma yok
/// 0.0–1.0 = devam ediyor
/// ViewModel onProgress callback'te bunu günceller; finally bloğu her zaman null'a döndürür.
final compressionProgressProvider = StateProvider<double?>((ref) => null);
