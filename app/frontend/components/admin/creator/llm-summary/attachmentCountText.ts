// @lat: [[testimony-attachment-warning-lists#attachmentCountText.ts centralizes the plural/count wording]]

export const plural = (count: number, word: string): string => (count > 1 ? `${word}s` : word);

export const attachmentCount = (count: number): string => (count > 1 ? ` (${count} attachments)` : "");
