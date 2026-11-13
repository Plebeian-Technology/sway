const SUMMARY_PLACEHOLDER = "Summary pending";

export const cleanFeedSummary = (summary: string | null | undefined): string | null => {
    if (!summary) {
        return null;
    }

    const cleaned = summary
        .replace(/NEWLINE/g, "\n")
        .replace(/ENDING/g, " ")
        .replace(/^\s*#{1,6}\s+/gm, "")
        .replace(/^\s*(?:[-*+]|\d+\.)\s+/gm, "")
        .replace(/^\s*>\s?/gm, "")
        .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
        .replace(/\*\*(.*?)\*\*/g, "$1")
        .replace(/(?<![A-Za-z0-9_])__([^\s_](?:[^_\n]*[^\s_])?)__(?![A-Za-z0-9_])/g, "$1")
        .replace(/(?<!\*)\*([^\s*](?:[^*\n]*[^\s*])?)\*(?!\*)/g, "$1")
        .replace(/(?<![A-Za-z0-9_])_([^\s_](?:[^_\n]*[^\s_])?)_(?![A-Za-z0-9_])/g, "$1")
        .replace(/`([^`]+)`/g, "$1")
        .replace(/\*\*/g, "")
        .replace(/\s+/g, " ")
        .trim();

    if (cleaned === "" || cleaned === SUMMARY_PLACEHOLDER) {
        return null;
    }

    return cleaned;
};
