export const BANNED_WORDS = [
    // This is a minimal list for demonstration/compliance. 
    // In a production app, this list should be expanded or replaced 
    // with a dedicated npm package like `bad-words` or a machine learning API.
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

/**
 * Basic profanity filter that replaces bad words with asterisks.
 */
export function censorProfanity(text: string): string {
    if (!text) return text;

    let censoredText = text;
    for (const badWord of BANNED_WORDS) {
        // Create a regex to find the bad word, case insensitive, globally
        // Using word boundaries \b to avoid replacing parts of legitimate words
        const regex = new RegExp(`\\b${badWord}\\b`, "gi");
        const replacement = "*".repeat(badWord.length);
        censoredText = censoredText.replace(regex, replacement);
    }

    return censoredText;
}
