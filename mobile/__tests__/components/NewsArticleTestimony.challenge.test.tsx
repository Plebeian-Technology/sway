// @lat: [[news-mobile-testimony#News mobile testimony]]
import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { NewsArticleTestimony, getAttribution } from "../../src/components/NewsArticleTestimony";
import type { NewsArticleTestimony as NewsArticleTestimonyType } from "../../src/types/bill";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { isSafeCitationUrl } from "../../src/utils/safeUrl";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("NewsArticleTestimony Empirical Adversarial Challenge Suite", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    const baseTestimony: NewsArticleTestimonyType = {
        id: 1,
        author_name: "Jane Columnist",
        outlet_name: "The Baltimore Sun",
        stance: "support",
        url: "https://baltimoresun.com/opinion/support-infrastructure",
        argument: "Investing in Baltimore infrastructure expands civic opportunities across all districts.",
    };

    describe("Vector 1: Malicious & Dangerous URL Schemes", () => {
        const maliciousSchemes = [
            { scheme: "javascript: (alert)", url: "javascript:alert(1)", desc: "Script alert execution" },
            { scheme: "javascript: (void)", url: "javascript:void(0)", desc: "Void script execution" },
            {
                scheme: "javascript: (complex)",
                url: "javascript:/*--></title></style></textarea></script><svg/onload=alert(document.domain)>",
                desc: "Complex polyglot script injection",
            },
            {
                scheme: "data: (html)",
                url: "data:text/html,<script>alert(1)</script>",
                desc: "Data URI inline HTML",
            },
            {
                scheme: "data: (base64)",
                url: "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
                desc: "Data URI base64 payload",
            },
            { scheme: "file: (unix)", url: "file:///etc/passwd", desc: "Local unix file leak" },
            {
                scheme: "file: (android)",
                url: "file:///android_asset/database.sqlite3",
                desc: "Android internal asset leak",
            },
            { scheme: "vbscript:", url: "vbscript:MsgBox(1)", desc: "VBScript injection" },
            {
                scheme: "intent:",
                url: "intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client.android;end",
                desc: "Android intent hijacking",
            },
            {
                scheme: "blob:",
                url: "blob:https://baltimoresun.com/d3b07384-d113-4a11-89e4-c8c7f99d9be8",
                desc: "Blob URL execution",
            },
            { scheme: "about:", url: "about:blank", desc: "Internal about:blank protocol" },
            { scheme: "chrome:", url: "chrome://settings", desc: "Internal browser settings scheme" },
            { scheme: "tel:", url: "tel:18005550199", desc: "Telephony dialer trigger" },
            { scheme: "sms:", url: "sms:18005550199?body=malicious", desc: "SMS composer trigger" },
            { scheme: "mailto:", url: "mailto:phishing@attacker.example.org", desc: "Mailto trigger" },
            { scheme: "ftp:", url: "ftp://attacker.example.org/exploit", desc: "Unencrypted FTP protocol" },
            { scheme: "ws:", url: "ws://attacker.example.org/socket", desc: "WebSocket unencrypted scheme" },
            { scheme: "wss:", url: "wss://attacker.example.org/socket", desc: "WebSocket encrypted scheme" },
        ];

        test.each(maliciousSchemes)("isSafeCitationUrl rejects malicious scheme: $scheme ($desc)", ({ url }) => {
            expect(isSafeCitationUrl(url)).toBe(false);
        });

        test.each(maliciousSchemes)(
            "renders outlet as inert plain text and blocks Linking.openURL for scheme: $scheme",
            ({ url, desc }) => {
                const testimony: NewsArticleTestimonyType = {
                    ...baseTestimony,
                    id: 101,
                    outlet_name: `Dangerous Outlet (${desc})`,
                    url,
                };

                wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);

                const outletText = screen.getByText(testimony.outlet_name);
                expect(outletText).toBeTruthy();
                expect(outletText.props.accessibilityRole).toBe("text");
                expect(screen.queryByRole("link", { name: testimony.outlet_name })).toBeNull();

                fireEvent.press(outletText);
                expect(openURLSpy).not.toHaveBeenCalled();
            },
        );

        test.each(maliciousSchemes)(
            "markdown links in argument with scheme $scheme render as inert plain text without link role",
            ({ url, desc }) => {
                const testimony: NewsArticleTestimonyType = {
                    ...baseTestimony,
                    id: 102,
                    argument: `Investigate this claim: [Exploit Source (${desc})](${url}) for full details.`,
                };

                wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);

                expect(screen.queryByRole("link", { name: `Exploit Source (${desc})` })).toBeNull();
                expect(
                    screen.getByText(new RegExp(`Exploit Source \\(${desc.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\)`)),
                ).toBeTruthy();
                expect(openURLSpy).not.toHaveBeenCalled();
            },
        );
    });

    describe("Vector 2: Credentials Embedded in URLs (Userinfo Smuggling)", () => {
        const credentialUrls = [
            { url: "https://user:pass@example.com", desc: "Username and password" },
            { url: "https://admin@example.com/secret", desc: "Username only" },
            { url: "https://:secret@example.com/vault", desc: "Password only" },
            { url: "http://developer:token_98765@news.baltimore.gov/api", desc: "HTTP token in userinfo" },
            { url: "https://user%40target.com:secret%21@example.com", desc: "Percent-encoded credentials" },
            { url: "https://root:toor@192.168.1.1/admin", desc: "Credentials with IP address" },
        ];

        test.each(credentialUrls)("isSafeCitationUrl rejects userinfo smuggling: $desc ($url)", ({ url }) => {
            expect(isSafeCitationUrl(url)).toBe(false);
        });

        test.each(credentialUrls)(
            "refuses credentials in citation URL and prevents navigation: $desc",
            ({ url, desc }) => {
                const testimony: NewsArticleTestimonyType = {
                    ...baseTestimony,
                    id: 201,
                    outlet_name: `Credentialed News (${desc})`,
                    url,
                };

                wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);

                const outletNode = screen.getByText(testimony.outlet_name);
                expect(outletNode.props.accessibilityRole).toBe("text");
                expect(screen.queryByRole("link", { name: testimony.outlet_name })).toBeNull();

                fireEvent.press(outletNode);
                expect(openURLSpy).not.toHaveBeenCalled();
            },
        );

        test("permits benign '@' characters inside URL query strings and fragments", () => {
            const safeQueryUrl = "https://example.com/opinion?contact=editor@baltimoresun.com";
            const safeFragmentUrl = "https://example.com/editorial#response@section";

            expect(isSafeCitationUrl(safeQueryUrl)).toBe(true);
            expect(isSafeCitationUrl(safeFragmentUrl)).toBe(true);

            wrap(
                <NewsArticleTestimony
                    testimonies={[
                        { ...baseTestimony, id: 202, outlet_name: "Query Outlet", url: safeQueryUrl },
                        { ...baseTestimony, id: 203, outlet_name: "Fragment Outlet", url: safeFragmentUrl },
                    ]}
                    stance="support"
                />,
            );

            const queryLink = screen.getByRole("link", { name: "Query Outlet" });
            const fragmentLink = screen.getByRole("link", { name: "Fragment Outlet" });

            expect(queryLink).toBeTruthy();
            expect(fragmentLink).toBeTruthy();

            fireEvent.press(queryLink);
            expect(openURLSpy).toHaveBeenCalledWith(safeQueryUrl);

            fireEvent.press(fragmentLink);
            expect(openURLSpy).toHaveBeenCalledWith(safeFragmentUrl);
        });
    });

    describe("Vector 3: Case-Sensitivity, Formatting & Scheme Normalization", () => {
        const validMixedCaseUrls = [
            { raw: "HTTPS://thebaltimorebanner.com/opinion/transit", desc: "Uppercase HTTPS" },
            { raw: "HttpS://thebaltimorebanner.com/opinion/transit", desc: "Mixed-case HttpS" },
            { raw: "HTTP://baltimoresun.com/opinion/editorial", desc: "Uppercase HTTP" },
            { raw: "hTtP://baltimoresun.com/opinion/editorial", desc: "Mixed-case hTtP" },
            { raw: "HTTPS://WWW.MARYLANDMATTERS.ORG/OPINION", desc: "Full uppercase URL" },
        ];

        test.each(validMixedCaseUrls)(
            "isSafeCitationUrl normalizes and accepts valid mixed-case scheme: $desc ($raw)",
            ({ raw }) => {
                expect(isSafeCitationUrl(raw)).toBe(true);
            },
        );

        test.each(validMixedCaseUrls)(
            "renders valid mixed-case citation URL as interactive link and opens on press: $desc",
            ({ raw, desc }) => {
                const testimony: NewsArticleTestimonyType = {
                    ...baseTestimony,
                    id: 301,
                    outlet_name: `Banner (${desc})`,
                    url: raw,
                };

                wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);

                const link = screen.getByRole("link", { name: testimony.outlet_name });
                expect(link).toBeTruthy();
                expect(link.props.accessibilityRole).toBe("link");

                fireEvent.press(link);
                expect(openURLSpy).toHaveBeenCalledWith(raw);
            },
        );

        const maliciousMixedCaseUrls = [
            { raw: "JAVASCRIPT:alert(1)", desc: "Uppercase JAVASCRIPT" },
            { raw: "Javascript:alert(1)", desc: "Capitalized Javascript" },
            { raw: "jAvAsCrIpT:void(0)", desc: "SpongeBob case jAvAsCrIpT" },
            { raw: "DATA:text/html,<script>alert(1)</script>", desc: "Uppercase DATA" },
            { raw: "Data:text/html;base64,PHNjcmlwdD4=", desc: "Capitalized Data" },
            { raw: "FILE:///etc/passwd", desc: "Uppercase FILE" },
            { raw: "File:///android_asset/secret", desc: "Capitalized File" },
            { raw: "VBSCRIPT:MsgBox(1)", desc: "Uppercase VBSCRIPT" },
            { raw: "InTent://scan", desc: "Mixed-case InTent" },
            { raw: "BLOB:https://example.com/uuid", desc: "Uppercase BLOB" },
            { raw: "About:blank", desc: "Capitalized About" },
        ];

        test.each(maliciousMixedCaseUrls)(
            "isSafeCitationUrl rejects mixed-case malicious scheme: $desc ($raw)",
            ({ raw }) => {
                expect(isSafeCitationUrl(raw)).toBe(false);
            },
        );

        test.each(maliciousMixedCaseUrls)(
            "renders inert text and suppresses openURL for mixed-case malicious URL: $desc",
            ({ raw, desc }) => {
                const testimony: NewsArticleTestimonyType = {
                    ...baseTestimony,
                    id: 302,
                    outlet_name: `Adversarial Outlet (${desc})`,
                    url: raw,
                };

                wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);

                expect(screen.queryByRole("link", { name: testimony.outlet_name })).toBeNull();
                const textNode = screen.getByText(testimony.outlet_name);
                expect(textNode.props.accessibilityRole).toBe("text");

                fireEvent.press(textNode);
                expect(openURLSpy).not.toHaveBeenCalled();
            },
        );

        test("accepts URLs with leading and trailing whitespace after trimming", () => {
            const paddedUrl = "   https://thebaltimorebanner.com/opinion/transit   ";
            expect(isSafeCitationUrl(paddedUrl)).toBe(true);

            const testimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 303,
                outlet_name: "Padded Outlet",
                url: paddedUrl,
            };

            wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);

            const link = screen.getByRole("link", { name: "Padded Outlet" });
            fireEvent.press(link);
            expect(openURLSpy).toHaveBeenCalledWith(paddedUrl);
        });

        test("rejects URLs with embedded whitespace or control characters in scheme/authority", () => {
            expect(isSafeCitationUrl("https ://example.com")).toBe(false);
            expect(isSafeCitationUrl("http s://example.com")).toBe(false);
            expect(isSafeCitationUrl("https:// example.com")).toBe(false);
            expect(isSafeCitationUrl("java script:alert(1)")).toBe(false);
            expect(isSafeCitationUrl("javascript :alert(1)")).toBe(false);
            expect(isSafeCitationUrl("jav\tascript:alert(1)")).toBe(false);
            expect(isSafeCitationUrl("java\0script:alert(1)")).toBe(false);
        });
    });

    describe("Vector 4: Scheme Bypasses & Inert Plain-Text Rendering", () => {
        test("ensures unsafe URLs render as inert plain text without press handlers, onOpenUrl is NOT invoked, and Linking.openURL is NOT called", () => {
            const onOpenUrlMock = jest.fn();
            const unsafeTestimonies: NewsArticleTestimonyType[] = [
                {
                    ...baseTestimony,
                    id: 401,
                    outlet_name: "Bypass Javascript Outlet",
                    url: "javascript:alert(1)",
                },
                {
                    ...baseTestimony,
                    id: 402,
                    outlet_name: "Bypass Data Outlet",
                    url: "data:text/html,payload",
                },
                {
                    ...baseTestimony,
                    id: 403,
                    outlet_name: "Bypass File Outlet",
                    url: "file:///etc/hosts",
                },
                {
                    ...baseTestimony,
                    id: 404,
                    outlet_name: "Bypass Credential Outlet",
                    url: "https://attacker:secret@malicious.example.com",
                },
            ];

            wrap(<NewsArticleTestimony testimonies={unsafeTestimonies} stance="support" onOpenUrl={onOpenUrlMock} />);

            for (const item of unsafeTestimonies) {
                expect(screen.queryByRole("link", { name: item.outlet_name })).toBeNull();
                const textElement = screen.getByText(item.outlet_name);
                expect(textElement.props.accessibilityRole).toBe("text");
                fireEvent.press(textElement);
            }

            expect(onOpenUrlMock).not.toHaveBeenCalled();
            expect(openURLSpy).not.toHaveBeenCalled();
        });

        test("null or empty URL renders inert plain text safely without crashing", () => {
            const noUrlTestimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 405,
                outlet_name: "Print Only Newspaper",
                url: null as unknown as string,
            };

            wrap(<NewsArticleTestimony testimonies={[noUrlTestimony]} stance="support" />);

            expect(screen.queryByRole("link", { name: "Print Only Newspaper" })).toBeNull();
            const textElement = screen.getByText("Print Only Newspaper");
            expect(textElement.props.accessibilityRole).toBe("text");

            fireEvent.press(textElement);
            expect(openURLSpy).not.toHaveBeenCalled();
        });
    });

    describe("Vector 5: Error Resilience & Promise Rejection Handling", () => {
        test("catches and swallows Linking.openURL promise rejection with Error object without crashing", async () => {
            const consoleErrorSpy = jest.spyOn(console, "error").mockImplementation(() => {});
            openURLSpy.mockRejectedValue(new Error("Simulated OS failure: No Activity found to handle Intent"));

            const testimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 501,
                outlet_name: "Rejection Outlet",
                url: "https://baltimoresun.com/opinion/rejection-test",
            };

            wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);

            const link = screen.getByRole("link", { name: "Rejection Outlet" });
            expect(link).toBeTruthy();

            expect(() => {
                fireEvent.press(link);
            }).not.toThrow();

            expect(openURLSpy).toHaveBeenCalledWith("https://baltimoresun.com/opinion/rejection-test");

            await waitFor(() => {
                expect(openURLSpy).toHaveBeenCalledTimes(1);
            });

            consoleErrorSpy.mockRestore();
        });

        test("catches and swallows Linking.openURL rejection when rejection is a non-Error string or primitive", async () => {
            openURLSpy.mockRejectedValue("Native bridge rejected openURL invocation");

            const testimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 502,
                outlet_name: "Primitive Rejection Outlet",
                url: "https://thebaltimorebanner.com/opinion/primitive-test",
            };

            wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);

            const link = screen.getByRole("link", { name: "Primitive Rejection Outlet" });
            expect(() => {
                fireEvent.press(link);
            }).not.toThrow();

            await waitFor(() => {
                expect(openURLSpy).toHaveBeenCalledWith("https://thebaltimorebanner.com/opinion/primitive-test");
            });
        });

        test("custom onOpenUrl callback overrides Linking.openURL and receives exact URL", () => {
            const onOpenUrlMock = jest.fn();
            const testimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 503,
                outlet_name: "Callback Outlet",
                url: "https://marylandmatters.org/opinion/callback-test",
            };

            wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" onOpenUrl={onOpenUrlMock} />);

            const link = screen.getByRole("link", { name: "Callback Outlet" });
            fireEvent.press(link);

            expect(onOpenUrlMock).toHaveBeenCalledTimes(1);
            expect(onOpenUrlMock).toHaveBeenCalledWith("https://marylandmatters.org/opinion/callback-test");
            expect(openURLSpy).not.toHaveBeenCalled();
        });
    });

    describe("Vector 6: Edge Cases in Attribution Formatting & Unicode Robustness", () => {
        test("author_name is null: falls back to '<outlet_name> Editorial Board'", () => {
            const testimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 601,
                author_name: null,
                outlet_name: "The Baltimore Sun",
            };

            expect(getAttribution(testimony)).toEqual({
                authorByline: "The Baltimore Sun Editorial Board",
                outletName: "The Baltimore Sun",
            });

            wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);
            expect(screen.getByText("The Baltimore Sun Editorial Board")).toBeTruthy();
        });

        test("author_name is undefined: falls back to '<outlet_name> Editorial Board'", () => {
            const testimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 602,
                author_name: undefined as unknown as string,
                outlet_name: "Maryland Matters",
            };

            expect(getAttribution(testimony)).toEqual({
                authorByline: "Maryland Matters Editorial Board",
                outletName: "Maryland Matters",
            });

            wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);
            expect(screen.getByText("Maryland Matters Editorial Board")).toBeTruthy();
        });

        test("author_name is empty string: falls back to '<outlet_name> Editorial Board'", () => {
            const testimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 603,
                author_name: "",
                outlet_name: "The Daily Record",
            };

            expect(getAttribution(testimony)).toEqual({
                authorByline: "The Daily Record Editorial Board",
                outletName: "The Daily Record",
            });

            wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);
            expect(screen.getByText("The Daily Record Editorial Board")).toBeTruthy();
        });

        test("author_name is whitespace-only string: falls back to '<outlet_name> Editorial Board'", () => {
            const testimony: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 604,
                author_name: "   \t\n  ",
                outlet_name: "The Washington Post",
            };

            expect(getAttribution(testimony)).toEqual({
                authorByline: "The Washington Post Editorial Board",
                outletName: "The Washington Post",
            });

            wrap(<NewsArticleTestimony testimonies={[testimony]} stance="support" />);
            expect(screen.getByText("The Washington Post Editorial Board")).toBeTruthy();
        });

        test("outlet_name containing 'Editorial Board' in mixed case: prevents duplicated suffix", () => {
            const testCases = [
                {
                    outlet: "The Baltimore Sun Editorial Board",
                    expectedByline: "The Baltimore Sun Editorial Board",
                },
                {
                    outlet: "Washington Post EDITORIAL BOARD",
                    expectedByline: "Washington Post EDITORIAL BOARD",
                },
                {
                    outlet: "Wall Street Journal editorial board",
                    expectedByline: "Wall Street Journal editorial board",
                },
                {
                    outlet: "Maryland Matters Editorial Board & Opinion Desk",
                    expectedByline: "Maryland Matters Editorial Board & Opinion Desk",
                },
            ];

            for (const { outlet, expectedByline } of testCases) {
                const testimony: NewsArticleTestimonyType = {
                    ...baseTestimony,
                    id: 605,
                    author_name: null,
                    outlet_name: outlet,
                };

                const attr = getAttribution(testimony);
                expect(attr.authorByline).toBe(expectedByline);
                expect(attr.authorByline).not.toMatch(/Editorial Board\s+Editorial Board/i);
            }
        });

        test("unicode author and outlet names render cleanly with exact accents and symbols", () => {
            const unicodeTestimonies: NewsArticleTestimonyType[] = [
                {
                    ...baseTestimony,
                    id: 606,
                    author_name: "Renée DesRosiers-Müller",
                    outlet_name: "Le Monde des Élus",
                },
                {
                    ...baseTestimony,
                    id: 607,
                    author_name: "José González-O'Connor",
                    outlet_name: "El Periódico de la Comunidad",
                },
                {
                    ...baseTestimony,
                    id: 608,
                    author_name: null,
                    outlet_name: "Crónica Global",
                },
            ];

            wrap(<NewsArticleTestimony testimonies={unicodeTestimonies} stance="support" />);

            expect(screen.getByText("By Renée DesRosiers-Müller")).toBeTruthy();
            expect(screen.getByText("Le Monde des Élus")).toBeTruthy();

            expect(screen.getByText("By José González-O'Connor")).toBeTruthy();
            expect(screen.getByText("El Periódico de la Comunidad")).toBeTruthy();

            expect(screen.getByText("Crónica Global Editorial Board")).toBeTruthy();
            expect(screen.getByText("Crónica Global")).toBeTruthy();
        });
    });

    describe("Vector 7: Zero-Node Invariants & Boundary Suppression", () => {
        test("renders null (0 nodes) when testimonies is undefined", () => {
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={undefined} />);
            expect(toJSON()).toBeNull();
        });

        test("renders null (0 nodes) when testimonies is null", () => {
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={null} />);
            expect(toJSON()).toBeNull();
        });

        test("renders null (0 nodes) when testimonies is empty array", () => {
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[]} />);
            expect(toJSON()).toBeNull();
        });

        test("renders null when items have empty string argument", () => {
            const emptyArg: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 701,
                argument: "",
            };
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[emptyArg]} stance="support" />);
            expect(toJSON()).toBeNull();
        });

        test("renders null when items have whitespace-only argument", () => {
            const whitespaceArg: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 702,
                argument: "   \t\n   ",
            };
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[whitespaceArg]} stance="support" />);
            expect(toJSON()).toBeNull();
        });

        test("renders null when item has invalid or unknown stance string", () => {
            const invalidStances = ["neutral", "undecided", "abstain", "", "SUPPORT", "OPPOSE", "123"];

            for (const invalidStance of invalidStances) {
                const invalidItem = {
                    ...baseTestimony,
                    id: 703,
                    stance: invalidStance as unknown as "support",
                };

                const { toJSON: toJSONFiltered } = wrap(
                    <NewsArticleTestimony testimonies={[invalidItem]} stance="support" />,
                );
                expect(toJSONFiltered()).toBeNull();

                const { toJSON: toJSONUnfiltered } = wrap(<NewsArticleTestimony testimonies={[invalidItem]} />);
                expect(toJSONUnfiltered()).toBeNull();
            }
        });

        test("stance='support' filters only support and renders null if only oppose exist", () => {
            const opposeItem: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 704,
                stance: "oppose",
            };
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[opposeItem]} stance="support" />);
            expect(toJSON()).toBeNull();
        });

        test("stance='oppose' filters only oppose and renders null if only support exist", () => {
            const supportItem: NewsArticleTestimonyType = {
                ...baseTestimony,
                id: 705,
                stance: "support",
            };
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[supportItem]} stance="oppose" />);
            expect(toJSON()).toBeNull();
        });

        test("filters out invalid items while cleanly rendering valid items in mixed collections", () => {
            const mixedItems = [
                { ...baseTestimony, id: 710, argument: "   " },
                { ...baseTestimony, id: 711, stance: "neutral" as unknown as "support" },
                { ...baseTestimony, id: 712, author_name: "Valid Author", argument: "Valid testimony argument." },
                { ...baseTestimony, id: 713, argument: "" },
            ];

            wrap(<NewsArticleTestimony testimonies={mixedItems} stance="support" />);

            expect(screen.getByText("By Valid Author")).toBeTruthy();
            expect(screen.getByText("Valid testimony argument.")).toBeTruthy();
            expect(screen.getAllByText("News commentary")).toHaveLength(1);
        });
    });

    describe("Vector 8: Interleaved Complex Multi-Item Stress Test", () => {
        test("correctly handles list of 50 interleaved testimonies with alternating stances, safe/unsafe URLs, and valid/invalid arguments", () => {
            const largeTestimonies: NewsArticleTestimonyType[] = Array.from({ length: 50 }, (_, i) => {
                const isEven = i % 2 === 0;
                const stance: "support" | "oppose" = i % 3 === 0 ? "oppose" : "support";
                const isSafeUrl = i % 4 !== 0;
                const hasValidArg = i % 10 !== 9;

                return {
                    id: 1000 + i,
                    author_name: isEven ? `Author ${i}` : null,
                    outlet_name: `Outlet ${i}`,
                    stance,
                    url: isSafeUrl ? `https://outlet${i}.example.com/opinion` : `javascript:alert(${i})`,
                    argument: hasValidArg ? `Argument ${i} supporting the position with critical commentary.` : "   ",
                };
            });

            wrap(<NewsArticleTestimony testimonies={largeTestimonies} stance="support" />);

            const expectedSupportItems = largeTestimonies.filter(
                (item) => item.stance === "support" && item.argument.trim().length > 0,
            );

            const renderedCommentaryBadges = screen.getAllByText("News commentary");
            expect(renderedCommentaryBadges.length).toBe(expectedSupportItems.length);

            for (const item of expectedSupportItems) {
                const safe = isSafeCitationUrl(item.url);
                if (safe) {
                    const link = screen.getByRole("link", { name: item.outlet_name });
                    expect(link).toBeTruthy();
                } else {
                    expect(screen.queryByRole("link", { name: item.outlet_name })).toBeNull();
                    const textNode = screen.getByText(item.outlet_name);
                    expect(textNode.props.accessibilityRole).toBe("text");
                }
            }
        });
    });
});
