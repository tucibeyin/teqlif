"""
LLM İlan Açıklaması Test Aracı

Kullanım:
  python scripts/test_prompts.py            # interaktif mod
  python scripts/test_prompts.py --batch    # hazır senaryo seti
  python scripts/test_prompts.py --debug    # prompt'ları da göster
"""
import sys
import os
import asyncio
import time
import argparse

parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(parent_dir)

from app.services.ml.llm_service import (
    generate_listing_description_stream,
    _generate_system_prompt,
    _generate_user_prompt,
    _build_suffix,
)

# ── Gerçek kategori slug'ları (DB + mobile ile eşleşmeli) ─────────────────────
CATEGORIES: list[tuple[str, str]] = [
    ("elektronik", "Elektronik"),
    ("vasita",     "Vasıta"),
    ("emlak",      "Emlak"),
    ("giyim",      "Giyim & Moda"),
    ("spor",       "Spor & Outdoor"),
    ("kitap",      "Kitap & Hobi"),
    ("ev",         "Ev & Yaşam"),
    ("diger",      "Diğer"),
]

CONDITIONS: list[tuple[str, str]] = [
    ("new",       "Sıfır (kutusunda)"),
    ("like_new",  "Az kullanılmış"),
    ("used",      "Kullanılmış"),
    ("damaged",   "Hasarlı / Arızalı"),
]

LOCATIONS = [
    "İstanbul", "Ankara", "İzmir", "Bursa", "Antalya",
    "Adana", "Gaziantep", "Trabzon", "Kocaeli", "Konya",
]

# ── Batch test senaryoları ─────────────────────────────────────────────────────
BATCH_SCENARIOS = [
    # (başlık, kategori_slug, condition_slug, fiyat, lokasyon)
    ("iPhone 14 Pro 256GB Space Black",  "elektronik", "like_new", 28000, "İstanbul"),
    ("2021 Honda Civic 1.5 Turbo Exec",  "vasita",     "used",     480000, "Ankara"),
    ("Boş arsa 300m² imarlı",            "emlak",      "new",      None,   "Bursa"),
    ("Nike Air Max 90 Erkek 42 Numara",  "giyim",      "used",     800,    None),
    ("Canon EOS R50 + 18-45mm Kit Lens", "elektronik", "damaged",  12000,  "İzmir"),
    ("Çekyat Koltuk Yatak Deri Köşe",   "ev",         "used",     4500,   "İstanbul"),
    ("Dumbbell Seti 2x20kg",             "spor",       "like_new", 1200,   None),
    ("Harry Potter Serisi 7 Kitap",      "kitap",      "used",     350,    "Gaziantep"),
    ("MacBook Pro M3 14 inç 16GB 512GB", "elektronik", "new",      65000,  None),
    ("Xiaomi Scooter Pro2 Elektrikli",   "vasita",     "damaged",  4200,   "İzmir"),
]


def _sep(char="─", n=56):
    print(char * n)


def _pick_from_list(items: list[tuple[str, str]], prompt: str) -> str:
    """Numaralı menüden seçim yaptırır, slug döner."""
    print(f"\n{prompt}")
    for i, (slug, label) in enumerate(items, 1):
        print(f"  {i:2d}. {label}  ({slug})")
    while True:
        raw = input("  Seçim (numara): ").strip()
        if raw.isdigit() and 1 <= int(raw) <= len(items):
            return items[int(raw) - 1][0]
        print("  Geçersiz seçim, tekrar dene.")


def _label(slug: str, mapping: list[tuple[str, str]]) -> str:
    return next((lbl for s, lbl in mapping if s == slug), slug)


async def _run_one(
    title: str,
    category: str,
    condition: str,
    price: float | None,
    location: str | None,
    debug: bool = False,
) -> None:
    _sep()
    print(f"  Başlık   : {title}")
    print(f"  Kategori : {_label(category, CATEGORIES)}  ({category})")
    print(f"  Durum    : {_label(condition, CONDITIONS)}  ({condition})")
    print(f"  Fiyat    : {f'{int(price):,} TL'.replace(',', '.') if price else '─'}")
    print(f"  Lokasyon : {location or '─'}")
    _sep()

    if debug:
        sys_p = _generate_system_prompt(category, condition)
        usr_p = _generate_user_prompt(title, category, condition)
        suffix = _build_suffix(price, location)
        print("\n[DEBUG] SYSTEM PROMPT:")
        print(sys_p)
        print("\n[DEBUG] USER PROMPT (LLM'e giden):")
        print(usr_p)
        print(f"\n[DEBUG] SUFFIX ŞABLON (Python'dan eklenen): {suffix or '─'}")
        _sep("·")

    print("\nLLM üretiyor...\n")
    print("  > ", end="", flush=True)

    t0 = time.perf_counter()
    first_token_t: float | None = None
    char_count = 0

    async for chunk in generate_listing_description_stream(
        title=title,
        category=category,
        condition=condition,
        price=price,
        location=location,
    ):
        if first_token_t is None:
            first_token_t = time.perf_counter()
        print(chunk, end="", flush=True)
        char_count += len(chunk)

    elapsed = time.perf_counter() - t0
    ttft = (first_token_t - t0) if first_token_t else elapsed
    approx_tokens = char_count // 3  # Türkçe ~3 char/token

    print(f"\n\n  ⏱  İlk token: {ttft:.2f}s  |  Toplam: {elapsed:.2f}s  |  ~{approx_tokens} token  |  {char_count} karakter")
    _sep()


async def interactive_mode(debug: bool) -> None:
    print()
    _sep("═")
    print("  LLM İLAN AÇIKLAMASI — İNTERAKTİF TEST")
    print("  Çıkmak için boş başlık bırak veya 'q' yaz")
    _sep("═")

    while True:
        title = input("\nİlan Başlığı: ").strip()
        if not title or title.lower() in ("q", "quit", "exit"):
            print("Çıkılıyor.")
            break

        category = _pick_from_list(CATEGORIES, "Kategori:")
        condition = _pick_from_list(CONDITIONS, "Ürün Durumu:")

        raw_price = input("\nFiyat (TL, boş bırakılabilir): ").strip()
        price = float(raw_price) if raw_price.replace(".", "").isdigit() else None

        print(f"\nLokasyon önerileri: {', '.join(LOCATIONS[:5])} ...")
        raw_loc = input("Lokasyon (boş bırakılabilir): ").strip()
        location = raw_loc or None

        try:
            await _run_one(title, category, condition, price, location, debug=debug)
        except KeyboardInterrupt:
            print("\nAtlandı.")
        except Exception as exc:
            print(f"\n[Hata]: {exc}")


async def batch_mode(debug: bool) -> None:
    print()
    _sep("═")
    print(f"  LLM İLAN AÇIKLAMASI — BATCH TEST  ({len(BATCH_SCENARIOS)} senaryo)")
    _sep("═")

    passed = failed = 0
    for i, (title, cat, cond, price, loc) in enumerate(BATCH_SCENARIOS, 1):
        print(f"\nSenaryo {i}/{len(BATCH_SCENARIOS)}")
        try:
            await _run_one(title, cat, cond, price, loc, debug=debug)
            passed += 1
        except Exception as exc:
            print(f"[HATA]: {exc}")
            failed += 1
        await asyncio.sleep(0.5)  # Ollama'ya nefes aldır

    _sep("═")
    print(f"  Sonuç: {passed} başarılı / {failed} başarısız")
    _sep("═")


def main() -> None:
    parser = argparse.ArgumentParser(description="LLM test aracı")
    parser.add_argument("--batch", action="store_true", help="Hazır senaryo seti çalıştır")
    parser.add_argument("--debug", action="store_true", help="Prompt'ları ekrana bas")
    args = parser.parse_args()

    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

    if args.batch:
        asyncio.run(batch_mode(debug=args.debug))
    else:
        asyncio.run(interactive_mode(debug=args.debug))


if __name__ == "__main__":
    main()
