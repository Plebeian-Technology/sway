// @lat: [[news-mobile-citations#Mobile summary citations#In-prose citation parsing]]
import React from "react";
import { Linking, Text } from "react-native";
import { isSafeCitationUrl } from "../utils/safeUrl";

export interface CitedMarkdownProps {
    content?: string | null;
    maxChars?: number;
    expanded?: boolean;
    testID?: string;
    className?: string;
    linkClassName?: string;
    selectable?: boolean;
    onOpenUrl?: (url: string) => void | Promise<void>;
}

export type MarkdownToken = { type: "text"; value: string } | { type: "link"; text: string; url: string };

export const MAX_TOKEN_CACHE_ENTRIES = 100;

const tokenCache = new Map<string, MarkdownToken[]>();

export function clearTokenizeMarkdownCache(): void {
    tokenCache.clear();
}

export function tokenizeMarkdown(rawContent: string | null | undefined): MarkdownToken[] {
    if (!rawContent) return [];

    const cached = tokenCache.get(rawContent);
    if (cached) {
        tokenCache.delete(rawContent);
        tokenCache.set(rawContent, cached);
        return cached;
    }

    const text = rawContent.replace(/NEWLINE|ENDING/g, " ");
    const tokens: MarkdownToken[] = [];
    let i = 0;
    let textStart = 0;

    while (i < text.length) {
        if (text[i] === "[") {
            const labelStart = i + 1;
            const labelEnd = text.indexOf("]", labelStart);
            if (labelEnd !== -1 && text[labelEnd + 1] === "(") {
                const urlStart = labelEnd + 2;
                let urlEnd = -1;
                let depth = 1;
                let hasSpace = false;
                for (let j = urlStart; j < text.length; j++) {
                    if (text[j] === " " || text[j] === "\t" || text[j] === "\n") {
                        hasSpace = true;
                        break;
                    }
                    if (text[j] === "(") {
                        depth++;
                    } else if (text[j] === ")") {
                        depth--;
                        if (depth === 0) {
                            urlEnd = j;
                            break;
                        }
                    }
                }

                if (urlEnd !== -1 && !hasSpace) {
                    if (i > textStart) {
                        tokens.push({ type: "text", value: text.slice(textStart, i) });
                    }
                    const label = text.slice(labelStart, labelEnd);
                    const url = text.slice(urlStart, urlEnd);
                    tokens.push({
                        type: "link",
                        text: label || url,
                        url,
                    });
                    i = urlEnd + 1;
                    textStart = i;
                    continue;
                }
            }
        }
        i++;
    }

    if (textStart < text.length) {
        tokens.push({ type: "text", value: text.slice(textStart) });
    }

    if (tokenCache.size >= MAX_TOKEN_CACHE_ENTRIES) {
        const oldestKey = tokenCache.keys().next().value;
        if (oldestKey !== undefined) {
            tokenCache.delete(oldestKey);
        }
    }

    tokenCache.set(rawContent, tokens);
    return tokens;
}

export function getVisibleLength(tokens: MarkdownToken[]): number {
    return tokens.reduce((acc, t) => acc + (t.type === "link" ? t.text.length : t.value.length), 0);
}

function hasRemainingTokens(tokens: MarkdownToken[], nextIndex: number): boolean {
    for (let j = nextIndex; j < tokens.length; j++) {
        const t = tokens[j];
        if (t.type === "link" && t.text.length > 0) return true;
        if (t.type === "text" && t.value.length > 0) return true;
    }
    return false;
}

export function truncateTokens(
    tokens: MarkdownToken[],
    maxChars: number,
): { tokens: MarkdownToken[]; isTruncated: boolean } {
    let visibleCount = 0;
    const result: MarkdownToken[] = [];
    let isTruncated = false;

    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token.type === "text") {
            const len = token.value.length;
            if (visibleCount + len <= maxChars) {
                result.push(token);
                visibleCount += len;
            } else {
                const remaining = maxChars - visibleCount;
                if (remaining > 0) {
                    result.push({ type: "text", value: token.value.slice(0, remaining) });
                    visibleCount += remaining;
                }
                isTruncated = true;
                break;
            }
        } else {
            if (visibleCount < maxChars) {
                result.push(token);
                visibleCount += token.text.length;
                if (visibleCount >= maxChars && hasRemainingTokens(tokens, i + 1)) {
                    isTruncated = true;
                    break;
                }
            } else {
                isTruncated = true;
                break;
            }
        }
    }

    return { tokens: result, isTruncated };
}

export function CitedMarkdown({
    content,
    maxChars,
    expanded,
    testID,
    className,
    linkClassName,
    selectable = false,
    onOpenUrl,
}: CitedMarkdownProps) {
    if (!content) return null;

    const allTokens = tokenizeMarkdown(content);
    const shouldTruncate = typeof maxChars === "number" && !expanded;
    const { tokens, isTruncated } = shouldTruncate
        ? truncateTokens(allTokens, maxChars)
        : { tokens: allTokens, isTruncated: false };

    const handlePress = (url: string) => {
        if (!isSafeCitationUrl(url)) return;
        if (onOpenUrl) {
            void onOpenUrl(url);
            return;
        }
        void Linking.openURL(url).catch(() => {});
    };

    return (
        <Text testID={testID} className={className} accessibilityRole="text" selectable={selectable}>
            {tokens.map((token, index) => {
                if (token.type === "link") {
                    const safe = isSafeCitationUrl(token.url);
                    if (!safe) {
                        return <React.Fragment key={index}>{token.text}</React.Fragment>;
                    }
                    return (
                        <Text
                            key={index}
                            accessibilityRole="link"
                            accessibilityLabel={token.text}
                            accessibilityHint="Opens article in browser"
                            className={
                                linkClassName ??
                                "text-accent-light dark:text-accent-dark font-open-sans-semibold underline"
                            }
                            onPress={() => handlePress(token.url)}
                        >
                            {token.text}
                        </Text>
                    );
                }
                return <React.Fragment key={index}>{token.value}</React.Fragment>;
            })}
            {isTruncated ? "…" : ""}
        </Text>
    );
}

export default CitedMarkdown;
