import json

files = {
    'tr': {'callMute': 'Sessiz', 'callVideo': 'Video', 'callSpeaker': 'Hoparlör', 'callChat': 'Sohbet', 'callAddPerson': 'Ekle'},
    'en': {'callMute': 'Mute', 'callVideo': 'Video', 'callSpeaker': 'Speaker', 'callChat': 'Chat', 'callAddPerson': 'Add'},
    'ru': {'callMute': 'Без звука', 'callVideo': 'Видео', 'callSpeaker': 'Динамик', 'callChat': 'Чат', 'callAddPerson': 'Добавить'},
    'ar': {'callMute': 'كتم', 'callVideo': 'فيديو', 'callSpeaker': 'مكبر الصوت', 'callChat': 'دردشة', 'callAddPerson': 'إضافة'}
}

for lang, data in files.items():
    path = f'mobile/lib/l10n/app_{lang}.arb'
    with open(path, 'r', encoding='utf-8') as f:
        arb = json.load(f)
    
    arb.update(data)
    
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(arb, f, ensure_ascii=False, indent=2)
        f.write('\n')

print("Updated ARB files.")
