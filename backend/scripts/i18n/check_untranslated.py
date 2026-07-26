import os
import sys
import json

mobile_l10n_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "mobile", "lib", "l10n")

def read_arb(lang):
    with open(os.path.join(mobile_l10n_dir, f"app_{lang}.arb"), "r", encoding="utf-8") as f:
        return json.load(f)

tr_arb = read_arb("tr")
en_arb = read_arb("en")
ar_arb = read_arb("ar")
ru_arb = read_arb("ru")

untranslated_en = []
untranslated_ar = []
untranslated_ru = []

for k, tr_val in tr_arb.items():
    if not k.startswith("opt_"):
        continue
    en_val = en_arb.get(k, "")
    ar_val = ar_arb.get(k, "")
    ru_val = ru_arb.get(k, "")
    
    # We want to see if EN/AR/RU equal TR, and TR has Turkish characters or words that aren't global brands/numbers
    # Global brands/numbers: alphanumeric, ASCII, common model names
    if en_val == tr_val:
        untranslated_en.append((k, tr_val))
    if ar_val == tr_val:
        untranslated_ar.append((k, tr_val))
    if ru_val == tr_val:
        untranslated_ru.append((k, tr_val))

print(f"Identical in EN (likely global brands/numbers or untranslated): {len(untranslated_en)}")
print(f"Identical in AR: {len(untranslated_ar)}")
print(f"Identical in RU: {len(untranslated_ru)}")

# Print sample of identical in AR to see if any Turkish words remained
print("\nSample identical in AR (should ONLY be global brands/numbers/models like BMW, Giulia, 16GB):")
for k, v in untranslated_ar[:40]:
    # Let's see if there are any Turkish characters like ç, ğ, ı, ö, ş, ü
    has_tr_char = any(c in "çğığöşüÇĞİÖŞÜ" for c in v)
    if has_tr_char or " " in v or len(v) > 15:
        print(f"  [CHECK NEEDED] {k}: {v}")

print("\nChecking for any Turkish characters in EN/AR/RU opt_* translations:")
for k, tr_val in tr_arb.items():
    if not k.startswith("opt_"): continue
    for lang, arb in [("EN", en_arb), ("AR", ar_arb), ("RU", ru_arb)]:
        val = arb.get(k, "")
        if any(c in "çğığöşüÇĞİÖŞÜ" for c in val):
            print(f"  [{lang} HAS TR CHARS] {k}: {val}")
