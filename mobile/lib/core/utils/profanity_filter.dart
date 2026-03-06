import 'dart:convert';

class ProfanityFilter {
  static const List<String> bannedWords = [
    "amk",
    "kaltak",
    "o.ç",
    "oç",
    "orospu",
    "siktir",
    "yavşak",
    "piç",
    "göt",
    "meme",
    "yarrak",
    "amcık",
    "kavat",
    "puşt"
  ];

  static String censor(String text) {
    if (text.isEmpty) return text;
    
    String censoredText = text;
    for (final word in bannedWords) {
      // Basic replacement for now. 
      // For more robust filtering, a regex with word boundaries would be better.
      final pattern = RegExp('\\b$word\\b', caseSensitive: false);
      if (pattern.hasMatch(censoredText)) {
        censoredText = censoredText.replaceAllMapped(pattern, (match) {
          return '*' * match.group(0)!.length;
        });
      }
    }
    return censoredText;
  }
}
