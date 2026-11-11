import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { sway } from "sway";

import NewsArticleTestimony from "app/frontend/components/bill/NewsArticleTestimony";

// @lat: [[news-web-testimony#Attribution fidelity and secure citation navigation]]
// @lat: [[news-web-testimony#Multi-theme layout integration]]

afterEach(cleanup);

describe("NewsArticleTestimony Empirical Challenge Suite", () => {
    describe("1. Malicious URL Schemes & Protocol Blocking", () => {
        const maliciousSchemes = [
            { scheme: "javascript:alert(1)", desc: "standard javascript: payload" },
            { scheme: "javascript:void(0)", desc: "javascript void payload" },
            { scheme: "JAVASCRIPT:alert(document.cookie)", desc: "uppercase JAVASCRIPT: scheme" },
            { scheme: "JaVaScRiPt:confirm(1)", desc: "mixed-case JaVaScRiPt: scheme" },
            { scheme: " \tjavascript:alert(1)", desc: "whitespace-padded javascript: scheme" },
            { scheme: "jav\tascript:alert(1)", desc: "tab-infiltrated javascript scheme" },
            { scheme: "javascript\n:alert(1)", desc: "newline-infiltrated javascript scheme" },
            { scheme: "javascript%3aalert(1)", desc: "url-encoded colon scheme" },
            {
                scheme: "javascript:/*--></title></style></textarea></script><svg/onload=alert(1)>",
                desc: "xss polyglot scheme",
            },
            { scheme: "data:text/html,<script>alert('xss')</script>", desc: "data: text/html HTML payload" },
            {
                scheme: "DATA:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
                desc: "uppercase DATA: base64 payload",
            },
            { scheme: "file:///etc/passwd", desc: "file: scheme targeting local unix file" },
            { scheme: "FILE:///C:/Windows/win.ini", desc: "uppercase FILE: scheme targeting windows path" },
            { scheme: "vbscript:msgbox('malicious')", desc: "vbscript: scheme execution" },
            { scheme: "VBSCRIPT:execute('evil')", desc: "uppercase VBSCRIPT: scheme" },
            {
                scheme: "intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client.android;end",
                desc: "intent: scheme",
            },
            { scheme: "blob:https://example.com/550e8400-e29b-41d4-a716-446655440000", desc: "blob: URL" },
            { scheme: "//attacker.com/phish", desc: "protocol-relative URL without http/https" },
            { scheme: "\\\\attacker.com\\phish", desc: "backslash protocol-relative URL" },
            { scheme: "ftp://files.example.com/exploit.exe", desc: "ftp: protocol" },
            { scheme: "ssh://root@192.168.1.1", desc: "ssh: protocol" },
            { scheme: "tel:+18005550199", desc: "tel: protocol" },
            { scheme: "mailto:phish@attacker.com", desc: "mailto: protocol" },
        ];

        maliciousSchemes.forEach(({ scheme, desc }) => {
            it(`refuses ${desc} (${scheme}) and renders inert plain text without an anchor`, () => {
                const testimony: sway.INewsArticleTestimony = {
                    id: 101,
                    author_name: "Hostile Actor",
                    outlet_name: "Adversarial News",
                    url: scheme,
                    stance: "support",
                    argument: `Probing malicious scheme: ${scheme}`,
                };

                const { container } = render(<NewsArticleTestimony testimonies={[testimony]} />);

                expect(screen.queryByRole("link")).toBeNull();
                expect(container.querySelector("a")).toBeNull();

                const outletText = screen.getByText("Adversarial News");
                expect(outletText).toBeInTheDocument();
                expect(outletText.tagName.toLowerCase()).toBe("span");
                expect(outletText).toHaveClass("font-semibold text-foreground/80");

                expect(screen.getByText((content) => content.includes("Probing malicious scheme"))).toBeInTheDocument();
            });
        });
    });

    describe("2. Scheme Smuggling, Normalization & Malformed URLs", () => {
        const validNormalizedSchemes = [
            { url: "hTTp://baltimorebanner.com/opinion/trees" },
            { url: "HTTPS://baltimoresun.com/opinion/support" },
            { url: "HtTpS://example.com/editorial" },
            { url: "http:foo.com" },
        ];

        validNormalizedSchemes.forEach(({ url }) => {
            it(`correctly normalizes and safely permits valid mixed-case or shorthand scheme: ${url}`, () => {
                const testimony: sway.INewsArticleTestimony = {
                    id: 201,
                    author_name: "Valid Author",
                    outlet_name: "Legit News",
                    url,
                    stance: "support",
                    argument: "Legitimate argument with normalized scheme.",
                };

                render(<NewsArticleTestimony testimonies={[testimony]} />);

                const link = screen.getByRole("link", { name: /Legit News/i });
                expect(link).toBeInTheDocument();
                expect(link).toHaveAttribute("href", url);
                expect(link).toHaveAttribute("target", "_blank");
                expect(link).toHaveAttribute("rel", "noopener noreferrer");
            });
        });

        it("refuses embedded credentials and renders inert text without an anchor", () => {
            const credentialUrl = "https://user:password@example.com/secure-opinion";
            const testimony: sway.INewsArticleTestimony = {
                id: 202,
                author_name: "Auth Author",
                outlet_name: "Auth News",
                url: credentialUrl,
                stance: "oppose",
                argument: "Opinion requiring authentication.",
            };

            expect(() => {
                render(<NewsArticleTestimony testimonies={[testimony]} />);
            }).not.toThrow();

            expect(screen.queryByRole("link")).toBeNull();
            const outletText = screen.getByText("Auth News");
            expect(outletText).toBeInTheDocument();
            expect(outletText.tagName.toLowerCase()).toBe("span");
            expect(outletText).toHaveClass("font-semibold text-foreground/80");
        });

        const malformedUrls = [
            "",
            "   ",
            "not-a-valid-url",
            "http//missing-colon.com",
            "https://",
            "http:://double-colon.com",
            "://missing-scheme.org",
            "http:// broken domain.com",
            "///just-slashes",
        ];

        malformedUrls.forEach((malformed) => {
            it(`gracefully refuses malformed URL '${malformed}' without crashing`, () => {
                const testimony: sway.INewsArticleTestimony = {
                    id: 203,
                    author_name: "Malformed Tester",
                    outlet_name: "Malformed Outlet",
                    url: malformed,
                    stance: "support",
                    argument: "Testing malformed URL handling.",
                };

                const { container } = render(<NewsArticleTestimony testimonies={[testimony]} />);

                expect(screen.queryByRole("link")).toBeNull();
                expect(container.querySelector("a")).toBeNull();
                expect(screen.getByText("Malformed Outlet")).toBeInTheDocument();
            });
        });
    });

    describe("3. Link Security & External Navigation Accessibility", () => {
        it("strictly enforces target='_blank', rel='noopener noreferrer', and screen reader text", () => {
            const testimony: sway.INewsArticleTestimony = {
                id: 301,
                author_name: "Security Auditor",
                outlet_name: "The Baltimore Sun",
                url: "https://baltimoresun.com/opinion/trees",
                stance: "support",
                argument: "Safe external citation test.",
            };

            const { container } = render(<NewsArticleTestimony testimonies={[testimony]} />);

            const link = screen.getByRole("link", { name: /The Baltimore Sun/i });
            expect(link).toHaveAttribute("target", "_blank");
            expect(link).toHaveAttribute("rel", "noopener noreferrer");

            const srText = screen.getByText("(opens in new tab)");
            expect(srText).toHaveClass("sr-only");

            const svgIcon = container.querySelector("svg");
            expect(svgIcon).not.toBeNull();
            expect(svgIcon).toHaveAttribute("aria-hidden", "true");
        });
    });

    describe("4. String Injection & XSS Escapement", () => {
        const xssPayloads = {
            script: "<script>alert('xss-author')</script>",
            img: '<img src="x" onerror="alert(\'img-xss\')" />',
            svg: "<svg/onload=alert('svg-xss')>",
            iframe: "<iframe src='javascript:alert(1)'></iframe>",
            details: "<details open ontoggle=alert('toggle')><summary>click</summary></details>",
            attributeBreakout: '">><script>alert("breakout")</script>',
        };

        it("escapes malicious HTML in author_name and renders it as pure text", () => {
            const testimony: sway.INewsArticleTestimony = {
                id: 401,
                author_name: xssPayloads.script,
                outlet_name: "Test Outlet",
                url: "https://example.com/test",
                stance: "support",
                argument: "Argument text.",
            };

            const { container } = render(<NewsArticleTestimony testimonies={[testimony]} />);

            expect(container.querySelector("script")).toBeNull();
            expect(screen.getByText(`By ${xssPayloads.script}`)).toBeInTheDocument();
        });

        it("escapes malicious HTML in outlet_name and renders it as pure text inside citation", () => {
            const testimony: sway.INewsArticleTestimony = {
                id: 402,
                author_name: "Jane Doe",
                outlet_name: xssPayloads.img,
                url: "https://example.com/test",
                stance: "support",
                argument: "Argument text.",
            };

            const { container } = render(<NewsArticleTestimony testimonies={[testimony]} />);

            expect(container.querySelector("img")).toBeNull();
            expect(screen.getByText(xssPayloads.img)).toBeInTheDocument();
        });

        it("escapes malicious HTML in argument and renders it as pure text", () => {
            const testimony: sway.INewsArticleTestimony = {
                id: 403,
                author_name: "Jane Doe",
                outlet_name: "Test Outlet",
                url: "https://example.com/test",
                stance: "support",
                argument: xssPayloads.iframe,
            };

            const { container } = render(<NewsArticleTestimony testimonies={[testimony]} />);

            expect(container.querySelector("iframe")).toBeNull();
            expect(screen.getByText(xssPayloads.iframe)).toBeInTheDocument();
        });

        it("safely handles XSS breakout attempts in URL parameter strings", () => {
            const maliciousQueryUrl = `https://example.com/article?search=${encodeURIComponent(xssPayloads.attributeBreakout)}`;
            const testimony: sway.INewsArticleTestimony = {
                id: 404,
                author_name: "URL Tester",
                outlet_name: "Query Outlet",
                url: maliciousQueryUrl,
                stance: "support",
                argument: "Testing URL breakout payload.",
            };

            const { container } = render(<NewsArticleTestimony testimonies={[testimony]} />);

            expect(container.querySelector("script")).toBeNull();
            const link = screen.getByRole("link", { name: /Query Outlet/i });
            expect(link).toHaveAttribute("href", maliciousQueryUrl);
        });
    });

    describe("5. Multi-Variant Layout Defense under Adversarial Input", () => {
        const adversarialTestimony: sway.INewsArticleTestimony = {
            id: 501,
            author_name: "<script>alert('author')</script>",
            outlet_name: "<b onmouseover='alert(1)'>Evil Outlet</b>",
            url: "javascript:alert('pwned')",
            stance: "support",
            argument: "<img src=x onerror=alert('argument') /> Policy argument",
        };

        const variants = ["default", "ballot", "banner", "cornerstore"] as const;

        variants.forEach((variant) => {
            it(`defends against adversarial payload in ${variant} variant`, () => {
                const { container } = render(
                    <NewsArticleTestimony testimonies={[adversarialTestimony]} variant={variant} />,
                );

                expect(container.querySelector("script")).toBeNull();
                expect(container.querySelector("img")).toBeNull();
                expect(container.querySelector("a")).toBeNull();
                expect(screen.queryByRole("link")).toBeNull();

                expect(screen.getByText("News commentary")).toBeInTheDocument();
                expect(screen.getByText("<b onmouseover='alert(1)'>Evil Outlet</b>")).toBeInTheDocument();
                expect(screen.getByText("<img src=x onerror=alert('argument') /> Policy argument")).toBeInTheDocument();
            });
        });
    });
});
