-- Favorilerden çıkarılmış ama listing_likes'ta kalan stale satırları temizler.
-- Neden oluştu: eski kod favorites API'sinden is_liked almıyordu,
-- unfavorite sırasında toggleLike hiç çağrılmıyordu.

-- 1. Kaç tane var?
SELECT COUNT(*) AS orphaned_likes
FROM listing_likes ll
LEFT JOIN favorites f ON f.user_id = ll.user_id AND f.listing_id = ll.listing_id
WHERE f.id IS NULL;

-- 2. Temizle:
DELETE FROM listing_likes
WHERE id IN (
    SELECT ll.id
    FROM listing_likes ll
    LEFT JOIN favorites f ON f.user_id = ll.user_id AND f.listing_id = ll.listing_id
    WHERE f.id IS NULL
);
