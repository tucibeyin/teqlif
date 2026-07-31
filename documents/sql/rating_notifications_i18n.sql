-- Push notification + bildirim ayarları için rating i18n key'leri
-- VPS'te psql ile çalıştır:
--   psql $DATABASE_URL -f rating_notifications_i18n.sql

INSERT INTO translations (lang, key, value) VALUES
  -- Push bildirimi içerik key'leri (@ prefix: Flutter regex ile username çekiyor)
  ('tr', 'notifRatingUpdatedTitle', '@{username} değerlendirmesini güncelledi'),
  ('en', 'notifRatingUpdatedTitle', '@{username} updated their rating'),
  ('ar', 'notifRatingUpdatedTitle', 'قام @{username} بتحديث تقييمه'),
  ('ru', 'notifRatingUpdatedTitle', '@{username} обновил оценку'),

  ('tr', 'notifRatingReplyTitle', '@{username} değerlendirmene yanıt verdi'),
  ('en', 'notifRatingReplyTitle', '@{username} replied to your rating'),
  ('ar', 'notifRatingReplyTitle', 'ردّ @{username} على تقييمك'),
  ('ru', 'notifRatingReplyTitle', '@{username} ответил на твой отзыв'),

  -- Bildirim ayarları ekranı toggle label'ları
  ('tr', 'notifSettingsRatingsTitle', 'Değerlendirme Bildirimleri'),
  ('en', 'notifSettingsRatingsTitle', 'Rating Notifications'),
  ('ar', 'notifSettingsRatingsTitle', 'إشعارات التقييم'),
  ('ru', 'notifSettingsRatingsTitle', 'Уведомления об оценках'),

  ('tr', 'notifSettingsRatingsDesc', 'Değerlendirme güncellendiğinde veya yanıtlandığında'),
  ('en', 'notifSettingsRatingsDesc', 'When a rating is updated or replied to'),
  ('ar', 'notifSettingsRatingsDesc', 'عند تحديث تقييم أو الرد عليه'),
  ('ru', 'notifSettingsRatingsDesc', 'При обновлении оценки или ответе на неё')

ON CONFLICT (lang, key) DO UPDATE SET value = EXCLUDED.value;
