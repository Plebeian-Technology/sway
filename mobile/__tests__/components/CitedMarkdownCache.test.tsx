import {
    clearTokenizeMarkdownCache,
    MAX_TOKEN_CACHE_ENTRIES,
    tokenizeMarkdown,
    truncateTokens,
} from "../../src/components/CitedMarkdown";

// @lat: [[news-mobile-citations#Mobile summary citations#In-prose citation parsing]]
describe("CitedMarkdown token caching", () => {
    beforeEach(() => {
        clearTokenizeMarkdownCache();
    });

    afterEach(() => {
        clearTokenizeMarkdownCache();
    });

    test("returns identical token array reference on repeated calls with identical input", () => {
        const passage = "News article passage citing [The Sun](https://baltimoresun.com/article) in testimony.";
        const first = tokenizeMarkdown(passage);
        const second = tokenizeMarkdown(passage);

        expect(first).toBe(second);
        expect(first).toEqual([
            { type: "text", value: "News article passage citing " },
            { type: "link", text: "The Sun", url: "https://baltimoresun.com/article" },
            { type: "text", value: " in testimony." },
        ]);
    });

    test("returns fresh token array when input text differs", () => {
        const passageA = "Passage mentioning [Source A](https://example.com/a).";
        const passageB = "Passage mentioning [Source B](https://example.com/b).";

        const tokensA = tokenizeMarkdown(passageA);
        const tokensB = tokenizeMarkdown(passageB);

        expect(tokensA).not.toBe(tokensB);
        expect(tokensA[1]).toEqual({ type: "link", text: "Source A", url: "https://example.com/a" });
        expect(tokensB[1]).toEqual({ type: "link", text: "Source B", url: "https://example.com/b" });
    });

    test("returns empty array immediately without caching on empty or falsy inputs", () => {
        expect(tokenizeMarkdown(null)).toEqual([]);
        expect(tokenizeMarkdown(undefined)).toEqual([]);
        expect(tokenizeMarkdown("")).toEqual([]);

        clearTokenizeMarkdownCache();
        expect(tokenizeMarkdown(null)).toEqual([]);
    });

    test("evicts least recently used entry when cache exceeds MAX_TOKEN_CACHE_ENTRIES", () => {
        expect(MAX_TOKEN_CACHE_ENTRIES).toBe(100);

        const firstEntryText = "entry-0-testimony";
        const firstEntryTokens = tokenizeMarkdown(firstEntryText);

        for (let i = 1; i < MAX_TOKEN_CACHE_ENTRIES; i++) {
            tokenizeMarkdown(`entry-${i}-testimony`);
        }

        const touchedFirst = tokenizeMarkdown(firstEntryText);
        expect(touchedFirst).toBe(firstEntryTokens);

        tokenizeMarkdown("overflow-entry-testimony");

        const subsequentFirst = tokenizeMarkdown(firstEntryText);
        expect(subsequentFirst).toBe(firstEntryTokens);

        const entry1Tokens = tokenizeMarkdown("entry-1-testimony");
        const entry1TokensSecond = tokenizeMarkdown("entry-1-testimony");
        expect(entry1TokensSecond).toBe(entry1Tokens);
    });

    test("evicts the first entry when entries are added sequentially without access", () => {
        const entries: string[] = [];
        const references: ReturnType<typeof tokenizeMarkdown>[] = [];

        for (let i = 0; i <= MAX_TOKEN_CACHE_ENTRIES; i++) {
            const text = `sequential-entry-${i}`;
            entries.push(text);
            references.push(tokenizeMarkdown(text));
        }

        const reFetchedFirst = tokenizeMarkdown(entries[0]);
        expect(reFetchedFirst).not.toBe(references[0]);
        expect(reFetchedFirst).toEqual(references[0]);

        const reFetchedLast = tokenizeMarkdown(entries[MAX_TOKEN_CACHE_ENTRIES]);
        expect(reFetchedLast).toBe(references[MAX_TOKEN_CACHE_ENTRIES]);
    });

    test("truncateTokens does not mutate the cached token array", () => {
        const passage = "Opening remarks with [Citation Link](https://example.com/ref) and substantial trailing text.";
        const cachedTokens = tokenizeMarkdown(passage);
        const initialLength = cachedTokens.length;
        const initialFirstTokenValue = cachedTokens[0].type === "text" ? cachedTokens[0].value : "";

        const { tokens: truncatedTokens, isTruncated } = truncateTokens(cachedTokens, 15);

        expect(isTruncated).toBe(true);
        expect(truncatedTokens).not.toBe(cachedTokens);

        const subsequentTokens = tokenizeMarkdown(passage);
        expect(subsequentTokens).toBe(cachedTokens);
        expect(subsequentTokens.length).toBe(initialLength);
        if (subsequentTokens[0].type === "text") {
            expect(subsequentTokens[0].value).toBe(initialFirstTokenValue);
        }
    });

    test("clearTokenizeMarkdownCache resets cache entries", () => {
        const passage = "Test passage for cache reset verification.";
        const first = tokenizeMarkdown(passage);

        clearTokenizeMarkdownCache();

        const second = tokenizeMarkdown(passage);
        expect(second).not.toBe(first);
        expect(second).toEqual(first);
    });
});
