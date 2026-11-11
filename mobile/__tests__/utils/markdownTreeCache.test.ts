import {
    clearMarkdownCache,
    MAX_MARKDOWN_CACHE_ENTRIES,
    parseMarkdown,
    truncateMarkdown,
    visibleText,
} from "../../src/utils/markdownTree";

// @lat: [[mobile-markdown-rendering#Parsing and truncation]]
describe("markdownTree AST caching", () => {
    beforeEach(() => {
        clearMarkdownCache();
    });

    afterEach(() => {
        clearMarkdownCache();
    });

    test("calling parseMarkdown twice with identical text returns the exact same Root AST reference", () => {
        const text = "A summary with **bold** text and [a link](https://example.com).";
        const ast1 = parseMarkdown(text);
        const ast2 = parseMarkdown(text);

        expect(ast1).toBe(ast2);
    });

    test("calling parseMarkdown with modified text produces a distinct Root with updated text", () => {
        const text1 = "Original bill description.";
        const text2 = "Original bill description!";
        const ast1 = parseMarkdown(text1);
        const ast2 = parseMarkdown(text2);

        expect(ast1).not.toBe(ast2);
        expect(visibleText(ast2)).toBe(text2);
    });

    test("truncateMarkdown does not mutate the cached AST on subsequent reads", () => {
        const text = "Long bill summary that exceeds normal preview boundaries.";
        const originalAst = parseMarkdown(text);
        const originalLength = visibleText(originalAst).length;

        const { tree: truncatedTree, isTruncated } = truncateMarkdown(originalAst, 15);
        expect(isTruncated).toBe(true);
        expect(visibleText(truncatedTree).length).toBeLessThanOrEqual(15);
        expect(truncatedTree).not.toBe(originalAst);

        const astAfter = parseMarkdown(text);
        expect(astAfter).toBe(originalAst);
        expect(visibleText(astAfter).length).toBe(originalLength);
    });

    test("exceeding MAX_MARKDOWN_CACHE_ENTRIES evicts least-recently-used string while retaining accessed string", () => {
        expect(MAX_MARKDOWN_CACHE_ENTRIES).toBe(100);

        const initialAst = parseMarkdown("item-0");
        let item1Ast = parseMarkdown("item-1");

        for (let i = 2; i < MAX_MARKDOWN_CACHE_ENTRIES; i++) {
            parseMarkdown(`item-${i}`);
        }

        const refreshedAst = parseMarkdown("item-0");
        expect(refreshedAst).toBe(initialAst);

        parseMarkdown("item-100");

        expect(parseMarkdown("item-0")).toBe(initialAst);
        expect(parseMarkdown("item-1")).not.toBe(item1Ast);
    });

    test("evicts FIFO entry when not refreshed", () => {
        const firstAst = parseMarkdown("first-entry");

        for (let i = 1; i < MAX_MARKDOWN_CACHE_ENTRIES; i++) {
            parseMarkdown(`entry-${i}`);
        }

        parseMarkdown("overflow-entry");

        const reParsedFirst = parseMarkdown("first-entry");
        expect(reParsedFirst).not.toBe(firstAst);
    });

    test("clearMarkdownCache flushes in-memory cache", () => {
        const text = "Cached text";
        const ast1 = parseMarkdown(text);
        clearMarkdownCache();
        const ast2 = parseMarkdown(text);

        expect(ast2).not.toBe(ast1);
    });
});
