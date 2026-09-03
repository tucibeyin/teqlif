import asyncio
import glob
import json
import logging
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from sqlalchemy import select, func
from app.database import AsyncSessionLocal
from app.models.state import State
from app.models.district import District
from app.models.listing import Listing

logger = logging.getLogger(__name__)

_COUNTRIES_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), '..', '..', 'documents', 'international', 'countries')
)


def _localized_country_name(code: str) -> str:
    try:
        from babel import Locale
        return Locale('tr').territories.get(code, code)
    except Exception:
        return code


async def sync_locations() -> None:
    json_files = glob.glob(os.path.join(_COUNTRIES_PATH, '*.json'))
    if not json_files:
        print("[sync_locations] JSON dosyası bulunamadı.")
        return

    print(f"[sync_locations] {len(json_files)} ülke dosyası okunuyor...")

    async with AsyncSessionLocal() as db:
        # countries tablosunu içe aktar (DB'de var, model şimdilik yok — raw SQL)
        from sqlalchemy import text

        # --- Ülkeler ---
        seen_country_codes: set[str] = set()
        for file_path in json_files:
            with open(file_path, encoding='utf-8') as f:
                data = json.load(f)

            code: str = data.get('code', '').upper()
            if not code:
                continue

            name = _localized_country_name(code)
            seen_country_codes.add(code)

            await db.execute(
                text("""
                    INSERT INTO countries (code, name)
                    VALUES (:code, :name)
                    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name
                """),
                {'code': code, 'name': name},
            )

        await db.flush()

        # --- İller (states) ---
        res = await db.execute(select(State))
        db_states: dict[str, State] = {s.name: s for s in res.scalars().all()}

        seen_state_names: set[str] = set()
        new_states: int = 0
        updated_states: int = 0

        for file_path in json_files:
            with open(file_path, encoding='utf-8') as f:
                data = json.load(f)

            country_code: str = data.get('code', '').upper()
            if not country_code:
                continue

            for sort_idx, state_data in enumerate(data.get('states', [])):
                state_name: str = state_data.get('name', '').strip()
                if not state_name:
                    continue

                seen_state_names.add(state_name)

                if state_name in db_states:
                    st = db_states[state_name]
                    st.sort_order = sort_idx
                    st.country_code = country_code
                    updated_states += 1
                else:
                    st = State(name=state_name, sort_order=sort_idx, country_code=country_code)
                    db.add(st)
                    new_states += 1
                    await db.flush()
                    db_states[state_name] = st

        await db.flush()

        # --- Silme: JSON'da olmayan iller ---
        deleted_states = 0
        skipped_states = 0
        for state_name, st in list(db_states.items()):
            if state_name in seen_state_names:
                continue
            # Guard: bu ile ait listing var mı? (location string eşleşmesi)
            count = await db.scalar(
                select(func.count()).select_from(Listing).where(Listing.location == state_name)
            )
            if count and count > 0:
                logger.warning(
                    "[sync_locations] İl '%s' JSON'da yok ama %d listing referans ediyor — silme atlandı.",
                    state_name, count,
                )
                skipped_states += 1
            else:
                # Önce bu ilin tüm ilçelerini sil
                await db.execute(
                    text("DELETE FROM districts WHERE state_id = :sid"),
                    {'sid': st.id},
                )
                await db.delete(st)
                deleted_states += 1

        await db.flush()

        # --- İlçeler (districts) ---
        res2 = await db.execute(select(District))
        db_districts: dict[tuple[int, str], District] = {
            (d.state_id, d.name): d for d in res2.scalars().all()
        }

        seen_district_keys: set[tuple[int, str]] = set()
        new_districts: int = 0

        for file_path in json_files:
            with open(file_path, encoding='utf-8') as f:
                data = json.load(f)

            for state_data in data.get('states', []):
                state_name = state_data.get('name', '').strip()
                st = db_states.get(state_name)
                if not st or not st.id:
                    continue

                for district_name in state_data.get('districts', []):
                    district_name = district_name.strip()
                    if not district_name:
                        continue

                    key = (st.id, district_name)
                    seen_district_keys.add(key)

                    if key not in db_districts:
                        d = District(state_id=st.id, name=district_name)
                        db.add(d)
                        db_districts[key] = d
                        new_districts += 1

        await db.flush()

        # --- Silme: JSON'da olmayan ilçeler ---
        deleted_districts = 0
        skipped_districts = 0
        for key, d in list(db_districts.items()):
            if key in seen_district_keys:
                continue
            count = await db.scalar(
                select(func.count()).select_from(Listing).where(Listing.district == d.name)
            )
            if count and count > 0:
                logger.warning(
                    "[sync_locations] İlçe '%s' JSON'da yok ama %d listing referans ediyor — silme atlandı.",
                    d.name, count,
                )
                skipped_districts += 1
            else:
                await db.delete(d)
                deleted_districts += 1

        await db.commit()

    print(
        f"[sync_locations] İller: +{new_states} yeni, {updated_states} güncellendi, "
        f"{deleted_states} silindi, {skipped_states} korundu."
    )
    print(
        f"[sync_locations] İlçeler: +{new_districts} yeni, "
        f"{deleted_districts} silindi, {skipped_districts} korundu."
    )


if __name__ == "__main__":
    asyncio.run(sync_locations())
