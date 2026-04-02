/// Güncel açık artırma fiyatına göre mantıklı teklif adımları üretir.
library;

/// Fiyat aralığına göre artış adımı döner.
int bidStep(int currentBid) {
  if (currentBid < 500)    return 25;
  if (currentBid < 1000)   return 50;
  if (currentBid < 2500)   return 100;
  if (currentBid < 5000)   return 250;
  if (currentBid < 10000)  return 500;
  if (currentBid < 25000)  return 1000;
  if (currentBid < 100000) return 2500;
  return 5000;
}

/// [currentBid]'den büyük, uygun artış adımlarına göre hizalanmış
/// [count] adet teklif seçeneği döner (küçükten büyüğe).
List<int> generateNextBids(int currentBid, int count) {
  final bids = <int>[];
  int price = currentBid;

  while (bids.length < count) {
    final step = bidStep(price);
    // Adıma hizala: bir sonraki "step katı" değerini bul
    final next = ((price ~/ step) + 1) * step;
    bids.add(next);
    price = next;
  }

  return bids;
}
