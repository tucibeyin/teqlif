IMAGE_MAX_BYTES         = 5 * 1024 * 1024    # 5 MB
VIDEO_MAX_BYTES         = 20 * 1024 * 1024   # 20 MB  (DM video — ≈15 sn iPhone MediumQuality)
LISTING_VIDEO_MAX_BYTES = 100 * 1024 * 1024  # 100 MB (İlan video ham input, ffmpeg remux sonrası küçülür)
VOICE_MAX_BYTES         = 512 * 1024          # 512 KB (64 kbps AAC ile ~60 sn)
FILE_MAX_BYTES          = 5 * 1024 * 1024    # 5 MB

VIDEO_MAX_SECS  = 15
VOICE_MAX_SECS  = 30

MSG_PAGE_SIZE   = 50
