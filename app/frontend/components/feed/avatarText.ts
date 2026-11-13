const LOCALE_ABBREVIATIONS: Record<string, string> = {
    Baltimore: "BAL",
    Maryland: "MD",
    "U.S. Congress": "US",
};

export const getLocaleAbbreviation = (localeName: string): string => {
    if (LOCALE_ABBREVIATIONS[localeName]) {
        return LOCALE_ABBREVIATIONS[localeName];
    }
    const words = localeName.trim().split(/\s+/);
    if (words.length >= 2) {
        return words
            .slice(0, 3)
            .map((w) => w[0]?.toUpperCase() ?? "")
            .join("");
    }
    return localeName.slice(0, 3).toUpperCase();
};

export const getInitials = (name: string): string => {
    const parts = name.trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return "?";
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return `${parts[0][0] ?? ""}${parts[parts.length - 1][0] ?? ""}`.toUpperCase();
};
