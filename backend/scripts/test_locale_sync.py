#!/usr/bin/env python3
"""
Faz 5: Test ve Doğrulama (Testing & Verification)
Sprint / Dil Senkronizasyonu Entegrasyon Testleri

Bu test scripti hem doğrudan `python test_locale_sync.py` ile hem de `pytest test_locale_sync.py` ile çalıştırılabilir.
"""
import asyncio
import os
import sys
from datetime import datetime, timezone, timedelta
from unittest.mock import AsyncMock, patch

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.schemas.user import UserUpdate, NotificationPrefs
from app.routers.auth import update_me, save_device_tokens, update_notification_prefs
from fastapi import Request


class MockUser:
    def __init__(self, id=1, locale="tr", locale_updated_at=None, **kwargs):
        self.id = id
        self.locale = locale
        self.locale_updated_at = locale_updated_at
        self.notification_prefs = {}
        for k, v in kwargs.items():
            setattr(self, k, v)


class MockAsyncSession:
    def __init__(self):
        self.committed = False
        self.refreshed = False
        self.executed_stmts = []

    async def commit(self):
        self.committed = True

    async def refresh(self, obj):
        self.refreshed = True

    async def execute(self, stmt):
        self.executed_stmts.append(stmt)
        class MockResult:
            def scalar_one_or_none(self):
                return None
        return MockResult()


async def async_test_5_1_offline_recovery_locale_persistence():
    print("\n[TEST 5.1a] Çevrimdışı (Offline) Dil Değişimi ve Bağlantı Yeniden Kurulma Testi...")
    
    # Uygulama çevrimdışıyken dil değiştiğinde istemci zaman damgası (örn: 1 saat önce)
    offline_time = datetime.now(timezone.utc) - timedelta(hours=1)
    user = MockUser(id=1, locale="tr", locale_updated_at=None)
    db = MockAsyncSession()

    update_payload = UserUpdate(locale="en", locale_updated_at=offline_time)

    with patch("app.utils.i18n.invalidate_user_i18n_caches", new_callable=AsyncMock) as mock_i18n_cache, \
         patch("app.routers.auth.invalidate_user_session_cache", new_callable=AsyncMock) as mock_sess_cache:
        
        updated_user = await update_me(data=update_payload, current_user=user, db=db)
        
        assert updated_user.locale == "en", f"Beklenen dil 'en', alınan '{updated_user.locale}'"
        assert updated_user.locale_updated_at == offline_time, "Offline zaman damgası DB'ye işlenemedi"
        assert db.committed is True, "DB commit çağrılmadı"
        assert db.refreshed is True, "DB refresh çağrılmadı"
        
        mock_i18n_cache.assert_called_once_with(1, "tr")
        print("✅ Başarılı: Çevrimdışı dil tercihleri bağlantı geldiğinde korundu ve önbellekler 'tr' için temizlendi.")


async def async_test_5_1_race_condition_stale_timestamp():
    print("\n[TEST 5.1b] Yarış Koşulu (Race Condition) / Eski Zaman Damgalı İstek Koruması...")
    
    # 1. Durum: Yeni zaman damgalı istek daha önce ulaşıp DB'ye işleniyor
    newer_time = datetime.now(timezone.utc)
    user = MockUser(id=1, locale="de", locale_updated_at=newer_time)
    db = MockAsyncSession()

    # 2. Durum: Gecikmeli (eski zaman damgalı) bir önceki istek geç ulaşıyor
    older_time = newer_time - timedelta(minutes=5)
    stale_payload = UserUpdate(locale="fr", locale_updated_at=older_time)

    with patch("app.utils.i18n.invalidate_user_i18n_caches", new_callable=AsyncMock) as mock_i18n_cache, \
         patch("app.routers.auth.invalidate_user_session_cache", new_callable=AsyncMock) as mock_sess_cache:
        
        updated_user = await update_me(data=stale_payload, current_user=user, db=db)
        
        # Doğrulama: Eski istek yoksayılmalı (should_update = False)
        assert updated_user.locale == "de", f"Eski istek dili ezdi! Beklenen 'de', alınan '{updated_user.locale}'"
        assert updated_user.locale_updated_at == newer_time, "Zaman damgası eski tarihle ezildi!"
        
        mock_i18n_cache.assert_not_called()
        mock_sess_cache.assert_called_once_with(1)
        print("✅ Başarılı: Eski zaman damgalı istek (fr) reddedildi, mevcut güncel dil (de) aktif kaldı.")


async def async_test_5_2_side_effect_device_tokens():
    print("\n[TEST 5.2a] Yan Etki İzolasyonu: /auth/device-tokens Uç Noktası...")
    
    user = MockUser(id=1, locale="tr", locale_updated_at=datetime.now(timezone.utc))
    db = MockAsyncSession()
    
    # Sahte bir Request nesnesi oluştur (Accept-Language: fr başlığı ile)
    scope = {
        "type": "http",
        "headers": [(b"accept-language", b"fr-FR,fr;q=0.9")],
        "query_string": b"",
        "path": "/api/auth/device-tokens"
    }
    request = Request(scope)
    payload = {"token": "fcm_test_token_12345", "voip_token": "voip_test_token_67890"}

    with patch("app.routers.auth.invalidate_user_session_cache", new_callable=AsyncMock) as mock_sess_cache:
        res = await save_device_tokens(request=request, payload=payload, current_user=user, db=db)
        
        assert res == {"ok": True}
        assert user.locale == "tr", f"Yan etki: Accept-Language (fr) DB dilini (tr) değiştirdi! Alınan: '{user.locale}'"
        assert db.committed is True
        
        # Execute edilen SQLAlchemy update ifadesinde 'locale' alanının olmadığından emin ol
        assert len(db.executed_stmts) > 0, "DB execute çağrılmadı"
        stmt_str = str(db.executed_stmts[0]).lower()
        assert "locale" not in stmt_str, f"SQL update sorgusu locale alanını değiştiriyor! Sorgu: {stmt_str}"
        
        print("✅ Başarılı: /auth/device-tokens uç noktasına Accept-Language: fr ile istek atıldığında users.locale değişmedi.")


async def async_test_5_2_side_effect_notification_prefs():
    print("\n[TEST 5.2b] Yan Etki İzolasyonu: /auth/notification-prefs Uç Noktası...")
    
    user = MockUser(id=1, locale="tr", locale_updated_at=datetime.now(timezone.utc))
    db = MockAsyncSession()
    
    prefs_data = NotificationPrefs(email=True, push=False, sms=True)
    
    with patch("app.routers.auth.invalidate_user_session_cache", new_callable=AsyncMock) as mock_sess_cache:
        res = await update_notification_prefs(data=prefs_data, current_user=user, db=db)
        
        assert res.email is True and res.push is False
        assert user.locale == "tr", f"Yan etki: bildirim ayarları güncellenirken dil değişti! Alınan: '{user.locale}'"
        assert db.committed is True
        assert db.refreshed is True
        
        print("✅ Başarılı: /auth/notification-prefs uç noktası users.locale değerini izole etti ve değiştirmedi.")


def test_5_1_offline_recovery_locale_persistence():
    asyncio.run(async_test_5_1_offline_recovery_locale_persistence())


def test_5_1_race_condition_stale_timestamp_protection():
    asyncio.run(async_test_5_1_race_condition_stale_timestamp())


def test_5_2_side_effect_isolation_device_tokens():
    asyncio.run(async_test_5_2_side_effect_device_tokens())


def test_5_2_side_effect_isolation_notification_prefs():
    asyncio.run(async_test_5_2_side_effect_notification_prefs())


if __name__ == "__main__":
    print("\n════════════════════════════════════════════════════════════════")
    print("  FAZ 5: TEST VE DOĞRULAMA (TESTING & VERIFICATION) SERİSİ")
    print("════════════════════════════════════════════════════════════════")
    try:
        test_5_1_offline_recovery_locale_persistence()
        test_5_1_race_condition_stale_timestamp_protection()
        test_5_2_side_effect_isolation_device_tokens()
        test_5_2_side_effect_isolation_notification_prefs()
        print("\n🎉 TÜM TESTLER BAŞARIYLA GEÇTİ (4/4 PASSED)!\n")
        sys.exit(0)
    except AssertionError as e:
        print(f"\n❌ TEST BAŞARISIZ OLDU: {e}\n")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ BEKLENMEYEN HATA: {type(e).__name__}: {e}\n")
        sys.exit(1)
