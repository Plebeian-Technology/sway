import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { RelatedNewsArticles } from "../../src/components/RelatedNewsArticles";
import type { RelatedNewsArticle } from "../../src/types/bill";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { isSafeCitationUrl } from "../../src/utils/safeUrl";

// Empirical Adversarial Challenge Suite for:
// Prerequisites:
// Related closed issues:
// Downstream dependents:

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("RelatedNewsArticles Empirical Adversarial Challenge Suite", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    const baseArticle: RelatedNewsArticle = {
        id: 1,
        title: "Default Title",
        outlet_name: "The Baltimore Sun",
        author_name: "Jane Doe",
        published_at: "2026-04-15T12:00:00Z",
        article_kind: "reporting",
        match_kind: "direct",
        url: "https://example.com/safe",
    };

    describe("Vector 1: Malicious & Non-Web Scheme Rejection", () => {
        const maliciousSchemes = [
            { scheme: "javascript:", url: "javascript:alert(document.cookie)", title: "JS Cookie Stealer" },
            { scheme: "data: (html)", url: "data:text/html,<script>alert(1)</script>", title: "Data HTML Script" },
            {
                scheme: "data: (base64)",
                url: "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
                title: "Data Base64 Payload",
            },
            { scheme: "file: (unix)", url: "file:///etc/passwd", title: "Local File Unix" },
            { scheme: "file: (android)", url: "file:///android_asset/secret.key", title: "Local File Android" },
            {
                scheme: "intent:",
                url: "intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client.android;end",
                title: "Android Intent Injection",
            },
            { scheme: "tel:", url: "tel:1234567890", title: "Dialer Injection" },
            {
                scheme: "blob:",
                url: "blob:https://example.com/d3b07384-d113-4a11-89e4-c8c7f99d9be8",
                title: "Blob URL",
            },
            { scheme: "custom-scheme:", url: "custom-app://open-payload", title: "Custom App Scheme" },
            { scheme: "mailto:", url: "mailto:phishing@target.org", title: "Mailto Scheme" },
            { scheme: "sms:", url: "sms:+1234567890?body=malicious", title: "SMS Scheme" },
            { scheme: "vbscript:", url: "vbscript:MsgBox(1)", title: "VBScript Injection" },
            { scheme: "about:", url: "about:blank", title: "About Scheme" },
            { scheme: "chrome:", url: "chrome://settings", title: "Internal Browser Scheme" },
            { scheme: "ftp:", url: "ftp://attacker.com/leak", title: "FTP Protocol" },
            { scheme: "ws:", url: "ws://attacker.com/stream", title: "WebSocket Unencrypted" },
            { scheme: "wss:", url: "wss://attacker.com/stream", title: "WebSocket Encrypted" },
        ];

        test.each(maliciousSchemes)("isSafeCitationUrl rejects $scheme ($url)", ({ url }) => {
            expect(isSafeCitationUrl(url)).toBe(false);
        });

        test.each(maliciousSchemes)(
            "renders inert text with accessibilityRole='text' and blocks Linking.openURL for $scheme",
            ({ url, title }) => {
                const article: RelatedNewsArticle = {
                    ...baseArticle,
                    id: 100,
                    title,
                    url,
                };

                wrap(<RelatedNewsArticles articles={[article]} />);

                const textElement = screen.getByText(title);
                expect(textElement).toBeTruthy();
                expect(textElement.props.accessibilityRole).toBe("text");

                expect(screen.queryByRole("link", { name: title })).toBeNull();

                fireEvent.press(textElement);
                expect(openURLSpy).not.toHaveBeenCalled();
            },
        );
    });

    describe("Vector 2: Scheme Smuggling, Normalization & Case Variations", () => {
        const mixedCaseValidUrls = [
            { raw: "HTTPS://example.com/transit", title: "Uppercase HTTPS" },
            { raw: "Http://example.com/housing", title: "Capitalized Http" },
            { raw: "hTtPs://example.com/budget", title: "Mixed-case hTtPs" },
            { raw: "HTTPS://WWW.BALTIMOREBANNER.COM/STORY", title: "Full Uppercase URL" },
        ];

        test.each(mixedCaseValidUrls)(
            "isSafeCitationUrl normalizes and accepts valid mixed-case scheme: $raw",
            ({ raw }) => {
                expect(isSafeCitationUrl(raw)).toBe(true);
            },
        );

        test.each(mixedCaseValidUrls)(
            "renders as interactive link with accessibilityRole='link' and opens URL for mixed-case: $raw",
            ({ raw, title }) => {
                const article: RelatedNewsArticle = {
                    ...baseArticle,
                    id: 200,
                    title,
                    url: raw,
                };

                wrap(<RelatedNewsArticles articles={[article]} />);

                const linkElement = screen.getByRole("link", { name: title });
                expect(linkElement).toBeTruthy();
                expect(linkElement.props.accessibilityRole).toBe("link");

                fireEvent.press(linkElement);
                expect(openURLSpy).toHaveBeenCalledWith(raw);
            },
        );

        const mixedCaseMaliciousUrls = [
            { raw: "JAVASCRIPT:alert(1)", desc: "Uppercase JAVASCRIPT" },
            { raw: "JavaScript:alert(1)", desc: "Mixed-case JavaScript" },
            { raw: "Data:text/html,abc", desc: "Capitalized Data" },
            { raw: "FILE:///etc/passwd", desc: "Uppercase FILE" },
            { raw: "InTent://scan", desc: "Mixed-case InTent" },
            { raw: "VBSCRIPT:MsgBox(1)", desc: "Uppercase VBSCRIPT" },
        ];

        test.each(mixedCaseMaliciousUrls)(
            "isSafeCitationUrl rejects mixed-case malicious scheme: $desc ($raw)",
            ({ raw }) => {
                expect(isSafeCitationUrl(raw)).toBe(false);
            },
        );

        test("accepts URLs with leading and trailing whitespace after trimming", () => {
            const paddedUrl = "   https://example.com/trimmed-path   ";
            expect(isSafeCitationUrl(paddedUrl)).toBe(true);

            const article: RelatedNewsArticle = {
                ...baseArticle,
                id: 201,
                title: "Trimmed Article",
                url: paddedUrl,
            };

            wrap(<RelatedNewsArticles articles={[article]} />);
            const link = screen.getByRole("link", { name: "Trimmed Article" });
            fireEvent.press(link);
            expect(openURLSpy).toHaveBeenCalledWith(paddedUrl);
        });

        test("rejects schemes with embedded whitespace or control characters", () => {
            expect(isSafeCitationUrl("java script:alert(1)")).toBe(false);
            expect(isSafeCitationUrl("javascript :alert(1)")).toBe(false);
            expect(isSafeCitationUrl("jav\tascript:alert(1)")).toBe(false);
            expect(isSafeCitationUrl("java\0script:alert(1)")).toBe(false);
            expect(isSafeCitationUrl("http s://example.com")).toBe(false);
            expect(isSafeCitationUrl("https ://example.com")).toBe(false);
        });
    });

    describe("Vector 3: User Credentials & Userinfo Smuggling", () => {
        const credentialUrls = [
            { url: "https://user:password@example.com/article", desc: "Username and password" },
            { url: "https://admin@example.com/article", desc: "Username only" },
            { url: "https://:secret@example.com/article", desc: "Password only" },
            { url: "http://developer:token_12345@news.baltimore.gov", desc: "HTTP with token credentials" },
            { url: "https://user%40domain.com:pass%23word@example.com", desc: "Percent-encoded credentials" },
            { url: "https://root:toor@192.168.1.1/secret", desc: "Credentials with IP address" },
        ];

        test.each(credentialUrls)("isSafeCitationUrl rejects credential smuggling: $desc ($url)", ({ url }) => {
            expect(isSafeCitationUrl(url)).toBe(false);
        });

        test.each(credentialUrls)(
            "renders title as inert text and refuses to open credentials URL: $desc",
            ({ url, desc }) => {
                const article: RelatedNewsArticle = {
                    ...baseArticle,
                    id: 300,
                    title: `Credential Leak ${desc}`,
                    url,
                };

                wrap(<RelatedNewsArticles articles={[article]} />);

                expect(screen.queryByRole("link", { name: article.title })).toBeNull();
                const textNode = screen.getByText(article.title);
                expect(textNode.props.accessibilityRole).toBe("text");

                fireEvent.press(textNode);
                expect(openURLSpy).not.toHaveBeenCalled();
            },
        );

        test("permits benign '@' characters in query parameters and fragments", () => {
            const searchUrl = "https://example.com/search?query=admin@domain.com";
            const fragmentUrl = "https://example.com/story#section@discussion";

            expect(isSafeCitationUrl(searchUrl)).toBe(true);
            expect(isSafeCitationUrl(fragmentUrl)).toBe(true);

            wrap(
                <RelatedNewsArticles
                    articles={[
                        { ...baseArticle, id: 301, title: "Search Email Query", url: searchUrl },
                        { ...baseArticle, id: 302, title: "Section Fragment", url: fragmentUrl },
                    ]}
                />,
            );

            expect(screen.getByRole("link", { name: "Search Email Query" })).toBeTruthy();
            expect(screen.getByRole("link", { name: "Section Fragment" })).toBeTruthy();
        });
    });

    describe("Vector 4: Protocol-Relative, Relative & Malformed URLs", () => {
        const invalidUrls = [
            { raw: "//example.com/article", desc: "Protocol-relative URL without scheme" },
            { raw: "/local/path/to/article", desc: "Root-relative path" },
            { raw: "article/details/123", desc: "Relative path without leading slash" },
            { raw: "", desc: "Empty string" },
            { raw: "   ", desc: "Whitespace string" },
            { raw: "\t\n", desc: "Tabs and newlines" },
            { raw: ":::", desc: "Invalid colons" },
            { raw: "https://", desc: "Scheme without authority" },
            { raw: "https:///", desc: "Scheme with slashes only" },
            { raw: "https://  ", desc: "Scheme with whitespace host" },
            { raw: "https://[invalid-ipv6", desc: "Malformed IPv6 syntax" },
            { raw: "not_a_valid_url", desc: "Bare alphanumeric string" },
        ];

        test.each(invalidUrls)("isSafeCitationUrl rejects invalid or relative URL: $desc ($raw)", ({ raw }) => {
            expect(isSafeCitationUrl(raw)).toBe(false);
        });

        test("isSafeCitationUrl rejects non-string types safely without throwing", () => {
            expect(isSafeCitationUrl(null)).toBe(false);
            expect(isSafeCitationUrl(undefined)).toBe(false);
            expect(isSafeCitationUrl(12345 as unknown as string)).toBe(false);
            expect(isSafeCitationUrl({} as unknown as string)).toBe(false);
            expect(isSafeCitationUrl([] as unknown as string)).toBe(false);
        });

        test.each(invalidUrls)("renders title as inert text and never triggers openURL for: $desc", ({ raw, desc }) => {
            const article: RelatedNewsArticle = {
                ...baseArticle,
                id: 400,
                title: `Invalid URL: ${desc}`,
                url: raw,
            };

            wrap(<RelatedNewsArticles articles={[article]} />);

            expect(screen.queryByRole("link", { name: article.title })).toBeNull();
            const textNode = screen.getByText(article.title);
            expect(textNode.props.accessibilityRole).toBe("text");

            fireEvent.press(textNode);
            expect(openURLSpy).not.toHaveBeenCalled();
        });
    });

    describe("Vector 5: Promise Rejection Resilience & Async Opener Resilience", () => {
        test("swallows Linking.openURL rejection gracefully without crashing or unhandled rejections", async () => {
            const consoleErrorSpy = jest.spyOn(console, "error").mockImplementation(() => {});
            openURLSpy.mockRejectedValue(new Error("Simulated OS failure: ActivityNotFoundException"));

            const safeArticle: RelatedNewsArticle = {
                ...baseArticle,
                id: 501,
                title: "Safe Article Rejection Test",
                url: "https://example.com/story-rejection",
            };

            wrap(<RelatedNewsArticles articles={[safeArticle]} />);

            const link = screen.getByRole("link", { name: "Safe Article Rejection Test" });
            expect(link).toBeTruthy();

            // Pressing must not throw synchronously
            expect(() => {
                fireEvent.press(link);
            }).not.toThrow();

            // Verify Linking.openURL was indeed called with the URL
            expect(openURLSpy).toHaveBeenCalledWith("https://example.com/story-rejection");

            // Await any microtasks/ticks to verify no unhandled rejection leaks
            await waitFor(() => {
                expect(openURLSpy).toHaveBeenCalledTimes(1);
            });

            consoleErrorSpy.mockRestore();
        });

        test("swallows Linking.openURL rejection when rejection is a non-Error object or primitive", async () => {
            openURLSpy.mockRejectedValue("String rejection from native bridge");

            const safeArticle: RelatedNewsArticle = {
                ...baseArticle,
                id: 502,
                title: "Non-Error Rejection Test",
                url: "https://example.com/non-error-rejection",
            };

            wrap(<RelatedNewsArticles articles={[safeArticle]} />);

            const link = screen.getByRole("link", { name: "Non-Error Rejection Test" });
            expect(() => {
                fireEvent.press(link);
            }).not.toThrow();

            await waitFor(() => {
                expect(openURLSpy).toHaveBeenCalledWith("https://example.com/non-error-rejection");
            });
        });

        test("onOpenUrl prop overrides Linking.openURL and receives exact sanitized URL", () => {
            const customOpenUrlMock = jest.fn();

            const safeArticle: RelatedNewsArticle = {
                ...baseArticle,
                id: 503,
                title: "Custom Opener Test",
                url: "https://example.com/custom-opener",
            };

            wrap(<RelatedNewsArticles articles={[safeArticle]} onOpenUrl={customOpenUrlMock} />);

            const link = screen.getByRole("link", { name: "Custom Opener Test" });
            fireEvent.press(link);

            expect(customOpenUrlMock).toHaveBeenCalledTimes(1);
            expect(customOpenUrlMock).toHaveBeenCalledWith("https://example.com/custom-opener");
            expect(openURLSpy).not.toHaveBeenCalled();
        });

        test("onOpenUrl is NOT called when article URL is unsafe", () => {
            const customOpenUrlMock = jest.fn();

            const unsafeArticle: RelatedNewsArticle = {
                ...baseArticle,
                id: 504,
                title: "Unsafe Custom Opener Test",
                url: "javascript:void(0)",
            };

            wrap(<RelatedNewsArticles articles={[unsafeArticle]} onOpenUrl={customOpenUrlMock} />);

            const textNode = screen.getByText("Unsafe Custom Opener Test");
            fireEvent.press(textNode);

            expect(customOpenUrlMock).not.toHaveBeenCalled();
            expect(openURLSpy).not.toHaveBeenCalled();
        });
    });

    describe("Vector 6: Mixed Interleaved Lists, Sequence & Boundary Robustness", () => {
        test("correctly discriminates safe vs unsafe links in an interleaved multi-article list", () => {
            const interleavedArticles: RelatedNewsArticle[] = [
                {
                    ...baseArticle,
                    id: 1,
                    title: "Article 1 (Safe HTTPS)",
                    url: "https://example.com/news/1",
                },
                {
                    ...baseArticle,
                    id: 2,
                    title: "Article 2 (Malicious JS)",
                    url: "javascript:alert(2)",
                },
                {
                    ...baseArticle,
                    id: 3,
                    title: "Article 3 (Safe HTTP)",
                    url: "http://example.com/news/3",
                },
                {
                    ...baseArticle,
                    id: 4,
                    title: "Article 4 (Credential Smuggling)",
                    url: "https://admin:pass@example.com/news/4",
                },
                {
                    ...baseArticle,
                    id: 5,
                    title: "Article 5 (Safe Mixed-case)",
                    url: "HTTPS://example.com/news/5",
                },
                {
                    ...baseArticle,
                    id: 6,
                    title: "Article 6 (File URI)",
                    url: "file:///etc/hosts",
                },
            ];

            wrap(<RelatedNewsArticles articles={interleavedArticles} />);

            // Check Article 1 (Safe)
            expect(screen.getByRole("link", { name: "Article 1 (Safe HTTPS)" })).toBeTruthy();
            fireEvent.press(screen.getByRole("link", { name: "Article 1 (Safe HTTPS)" }));
            expect(openURLSpy).toHaveBeenLastCalledWith("https://example.com/news/1");

            // Check Article 2 (Unsafe)
            expect(screen.queryByRole("link", { name: "Article 2 (Malicious JS)" })).toBeNull();
            expect(screen.getByText("Article 2 (Malicious JS)").props.accessibilityRole).toBe("text");
            fireEvent.press(screen.getByText("Article 2 (Malicious JS)"));
            expect(openURLSpy).toHaveBeenCalledTimes(1); // Still 1 from Article 1

            // Check Article 3 (Safe)
            expect(screen.getByRole("link", { name: "Article 3 (Safe HTTP)" })).toBeTruthy();
            fireEvent.press(screen.getByRole("link", { name: "Article 3 (Safe HTTP)" }));
            expect(openURLSpy).toHaveBeenLastCalledWith("http://example.com/news/3");

            // Check Article 4 (Unsafe)
            expect(screen.queryByRole("link", { name: "Article 4 (Credential Smuggling)" })).toBeNull();
            expect(screen.getByText("Article 4 (Credential Smuggling)").props.accessibilityRole).toBe("text");
            fireEvent.press(screen.getByText("Article 4 (Credential Smuggling)"));
            expect(openURLSpy).toHaveBeenCalledTimes(2); // Still 2

            // Check Article 5 (Safe)
            expect(screen.getByRole("link", { name: "Article 5 (Safe Mixed-case)" })).toBeTruthy();
            fireEvent.press(screen.getByRole("link", { name: "Article 5 (Safe Mixed-case)" }));
            expect(openURLSpy).toHaveBeenLastCalledWith("HTTPS://example.com/news/5");

            // Check Article 6 (Unsafe)
            expect(screen.queryByRole("link", { name: "Article 6 (File URI)" })).toBeNull();
            expect(screen.getByText("Article 6 (File URI)").props.accessibilityRole).toBe("text");
            fireEvent.press(screen.getByText("Article 6 (File URI)"));
            expect(openURLSpy).toHaveBeenCalledTimes(3); // Still 3
        });

        test("stress: 50 items with alternating safe and adversarial URLs maintain invariant integrity", () => {
            const stressArticles: RelatedNewsArticle[] = Array.from({ length: 50 }, (_, i) => {
                const isEven = i % 2 === 0;
                return {
                    id: i + 1,
                    title: `Stress Article #${i + 1} (${isEven ? "Safe" : "Unsafe"})`,
                    outlet_name: `Outlet ${i + 1}`,
                    author_name: isEven ? `Author ${i + 1}` : null,
                    published_at: isEven ? "2026-04-10T00:00:00Z" : null,
                    article_kind: isEven ? "reporting" : "opinion",
                    match_kind: isEven ? "direct" : "context",
                    url: isEven ? `https://outlet-${i + 1}.com/article` : `javascript:alert(${i + 1})`,
                };
            });

            wrap(<RelatedNewsArticles articles={stressArticles} />);

            const allLinks = screen.getAllByRole("link");
            expect(allLinks.length).toBe(25); // Exactly 25 even items

            // Verify each link has correct accessibility and maps to correct URL
            for (let i = 0; i < 50; i += 2) {
                const title = `Stress Article #${i + 1} (Safe)`;
                const link = screen.getByRole("link", { name: title });
                expect(link).toBeTruthy();
            }

            // Verify each odd item has role text and no link
            for (let i = 1; i < 50; i += 2) {
                const title = `Stress Article #${i + 1} (Unsafe)`;
                expect(screen.queryByRole("link", { name: title })).toBeNull();
                expect(screen.getByText(title).props.accessibilityRole).toBe("text");
            }
        });

        test("handles corrupt published_at dates gracefully without throwing", () => {
            const malformedDateArticles: RelatedNewsArticle[] = [
                { ...baseArticle, id: 601, title: "Invalid Date String", published_at: "not-a-date-at-all" },
                { ...baseArticle, id: 602, title: "Nonsense Epoch Date", published_at: "NaN" },
                { ...baseArticle, id: 603, title: "Empty Date String", published_at: "" },
            ];

            expect(() => {
                wrap(<RelatedNewsArticles articles={malformedDateArticles} />);
            }).not.toThrow();

            expect(screen.getByText("Invalid Date String")).toBeTruthy();
            expect(screen.getByText("Nonsense Epoch Date")).toBeTruthy();
            expect(screen.getByText("Empty Date String")).toBeTruthy();
        });
    });
});
