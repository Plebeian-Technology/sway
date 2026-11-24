// @lat: [[mobile-bill-surface-components-design#DistrictVotesPanel]]
import React from "react";
import { fireEvent, render, screen, within } from "@testing-library/react-native";

import { DistrictVotesPanel } from "../../src/components/DistrictVotesPanel";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { swayTokens } from "../../src/theme/tokens";
import { selectDistrictVotes, type DistrictRef } from "../../src/utils/districtVotes";

const scoreRow = (
    number: number,
    forCount: number,
    againstCount: number,
    regionCode = "MD",
    legislatorNames?: string[],
) => ({
    bill_score_id: 9,
    district: { name: `MD${number}`, number, region_code: regionCode },
    comparison_suppressed: false,
    for_percent: Math.round((forCount / (forCount + againstCount)) * 100),
    against_percent: 100 - Math.round((forCount / (forCount + againstCount)) * 100),
    at_large: false,
    ...(legislatorNames ? { legislator_names: legislatorNames } : {}),
});

const styleOf = (element: { props: { style?: unknown } }) =>
    Object.assign({}, ...[element.props.style].flat(Infinity).filter(Boolean));

const READER: DistrictRef = { name: "MD3", number: 3, region_code: "MD" };

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const panel = (
    scores: ReturnType<typeof scoreRow>[],
    readers: DistrictRef[] = [],
    userVoteSupport: "for" | "against" | null = null,
) => <DistrictVotesPanel votes={selectDistrictVotes(scores, readers)} userVoteSupport={userVoteSupport} />;

describe("DistrictVotesPanel", () => {
    const scores = [scoreRow(1, 12, 8), scoreRow(2, 3, 4), scoreRow(3, 9, 1), scoreRow(0, 50, 50)];

    test("draws a for/against pair per district and skips the at-large district", () => {
        wrap(panel(scores));

        expect(screen.getByTestId("district-votes-panel")).toBeTruthy();
        expect(screen.getAllByText("District 1")).toHaveLength(2);
        expect(screen.getAllByText("District 2")).toHaveLength(2);
        expect(screen.getAllByText("District 3")).toHaveLength(2);
        expect(screen.queryByText("District 0")).toBeNull();
        expect(screen.getByTestId("district-votes-row-1")).toBeTruthy();
    });

    test("the by-district chart is one accessible element that reads each district's tally", () => {
        wrap(panel(scores));

        const chart = screen.getByTestId("district-votes-chart");
        expect(chart.props.accessible).toBe(true);
        expect(chart.props.accessibilityLabel).toBe(
            "Votes by district. District 1: 60 percent for, 40 percent against. District 2: 43 percent for, 57 percent against. District 3: 90 percent for, 10 percent against.",
        );
    });

    test("the net chart is one accessible element that reads signed nets", () => {
        wrap(panel(scores));

        const chart = screen.getByTestId("district-affinity-chart");
        expect(chart.props.accessible).toBe(true);
        expect(chart.props.accessibilityLabel).toBe(
            "Net lean by district, percent for minus percent against. District 1: plus 20 points. District 2: minus 14 points. District 3: plus 80 points.",
        );
        expect(screen.getByText("+20%")).toBeTruthy();
        expect(screen.getByText("-14%")).toBeTruthy();
        expect(screen.getByText("+80%")).toBeTruthy();
    });

    test("each bar is as wide as its percentage", () => {
        wrap(panel(scores));

        const width = (id: string) => {
            const style = screen.getByTestId(id).props.style;
            return [style].flat(Infinity).find((s) => s && typeof s === "object" && "width" in s)?.width;
        };
        expect(width("district-votes-for-fill-1")).toBe("60%");
        expect(width("district-votes-against-fill-1")).toBe("40%");
    });

    test("net bars grow from the centre line, to the right for net for and to the left for net against", () => {
        wrap(panel([scoreRow(1, 10, 2), scoreRow(2, 2, 10)]));

        const place = (id: string) => {
            const style = screen.getByTestId(id).props.style;
            const flat = Object.assign({}, ...[style].flat(Infinity).filter(Boolean));
            return { left: flat.left, width: flat.width };
        };
        expect(place("district-affinity-fill-1")).toEqual({ left: "50%", width: "33%" });
        expect(place("district-affinity-fill-2")).toEqual({ left: "17%", width: "33%" });
    });

    test("draws an empty net bar for a perfectly tied district", () => {
        wrap(panel([scoreRow(1, 5, 5)]));

        const fill = screen.getByTestId("district-affinity-fill-1");
        expect(styleOf(fill).width).toBe("0%");
        expect(screen.getByText("0%")).toBeTruthy();
    });

    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    test("draws nothing when no district reaches the minimum and the reader has no district", () => {
        const hidden = { ...scoreRow(1, 6, 3), comparison_suppressed: true, for_percent: null, against_percent: null };
        const votes = selectDistrictVotes([hidden, scoreRow(0, 4, 4)], []);

        const { toJSON } = wrap(<DistrictVotesPanel votes={votes} />);

        expect(toJSON()).toBeNull();
    });

    test("shows no count anywhere in the panel", () => {
        wrap(panel([scoreRow(1, 1234, 567)], [{ name: "MD1", number: 1, region_code: "MD" }], "for"));

        const text = JSON.stringify(screen.toJSON());
        expect(text).not.toMatch(/1,?234|567/);
        expect(screen.getAllByText("69%").length).toBeGreaterThan(0);
    });

    describe("tracks and text at large type sizes", () => {
        test("every empty track is a token that stands apart from the card in dark mode, and unchanged in light mode", () => {
            wrap(panel(scores, [READER]));

            [
                "district-votes-reader-track",
                "district-votes-for-track-1",
                "district-votes-against-track-1",
                "district-affinity-track-1",
            ].forEach((id) => {
                const className = String(screen.getByTestId(id).props.className);
                expect(className).toContain("bg-muted-light");
                expect(className).toContain("dark:bg-border-dark");
                expect(className).not.toContain("dark:bg-muted-dark");
            });
        });

        test("district labels grow with the text and never truncate", () => {
            wrap(panel([scoreRow(12, 5, 3), scoreRow(1, 2, 1)]));

            screen.getAllByText("District 12").forEach((label) => {
                expect(label.props.numberOfLines).toBeUndefined();
                const style = Object.assign({}, ...[label.props.style].flat(Infinity).filter(Boolean));
                expect(style.minWidth).toBeGreaterThan(0);
                expect(style.width).toBeUndefined();
            });
        });

        test("counts grow with the text", () => {
            wrap(panel([scoreRow(12, 1234, 567)]));

            [screen.getByText("69%"), screen.getByText("31%")].forEach((count) => {
                const style = Object.assign({}, ...[count.props.style].flat(Infinity).filter(Boolean));
                expect(style.minWidth).toBeGreaterThan(0);
                expect(style.width).toBeUndefined();
            });
        });

        test("the legends wrap onto a second line instead of overflowing", () => {
            wrap(panel(scores));

            ["district-votes-legend", "district-affinity-legend"].forEach((id) => {
                expect(String(screen.getByTestId(id).props.className)).toContain("flex-wrap");
            });
        });

        test("the reader's tally row wraps onto a second line instead of overflowing", () => {
            wrap(panel(scores, [READER]));

            expect(String(screen.getByTestId("district-votes-reader-tally").props.className)).toContain("flex-wrap");
        });
    });

    describe("the reader's own district", () => {
        test("is called out above the charts with its tally", () => {
            wrap(panel(scores, [READER]));

            const block = screen.getByTestId("district-votes-reader");
            expect(block).toBeTruthy();
            expect(screen.getByText("Your district")).toBeTruthy();
            expect(screen.getByText("For: 90%")).toBeTruthy();
            expect(screen.getByText("Against: 10%")).toBeTruthy();
        });

        test("is highlighted in both charts and named as the reader's in the spoken label", () => {
            wrap(panel(scores, [READER]));

            expect(screen.getByTestId("district-votes-chart").props.accessibilityLabel).toContain(
                "District 3, your district: 90 percent for, 10 percent against.",
            );
            expect(screen.getByTestId("district-affinity-chart").props.accessibilityLabel).toContain(
                "District 3, your district: plus 80 points.",
            );
            const background = (id: string) =>
                Object.assign({}, ...[screen.getByTestId(id).props.style].flat(Infinity).filter(Boolean))
                    .backgroundColor;
            expect(background("district-votes-row-3")).toBe(swayTokens.light.surface3);
            expect(background("district-votes-row-1")).toBeUndefined();
        });

        test("is absent for a reader with no district of their own", () => {
            wrap(panel(scores, []));
            expect(screen.queryByTestId("district-votes-reader")).toBeNull();
            expect(screen.queryByText("Your district")).toBeNull();
        });

        // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
        test("says there are not enough votes yet when it has no row, and claims no alignment", () => {
            wrap(panel(scores, [{ name: "MD7", number: 7, region_code: "MD" }], "for"));
            expect(screen.getByTestId("district-votes-reader")).toBeTruthy();
            expect(screen.getByText("District 7")).toBeTruthy();
            expect(screen.getByTestId("district-votes-reader-suppressed")).toHaveTextContent("Not enough votes yet");
            expect(screen.queryByTestId("district-votes-alignment")).toBeNull();
            expect(screen.queryByTestId("district-votes-row-7")).toBeNull();
        });
    });

    describe("the alignment statement", () => {
        test("says the vote matches when the reader voted with the district's majority", () => {
            wrap(panel(scores, [READER], "for"));
            expect(screen.getByTestId("district-votes-alignment")).toHaveTextContent(
                "Your vote matches your district's majority.",
            );
        });

        test("says the vote differs when the reader voted against the district's majority", () => {
            wrap(panel(scores, [READER], "against"));
            expect(screen.getByTestId("district-votes-alignment")).toHaveTextContent(
                "Your vote differs from your district's majority.",
            );
        });

        test("is neutral when the district is evenly split", () => {
            wrap(panel([scoreRow(3, 4, 4), scoreRow(1, 1, 0)], [READER], "for"));
            expect(screen.getByTestId("district-votes-alignment")).toHaveTextContent("Your district is evenly split.");
        });

        test("is absent when the reader has not voted", () => {
            wrap(panel(scores, [READER], null));
            expect(screen.queryByTestId("district-votes-alignment")).toBeNull();
        });
    });

    // @lat: [[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]]
    describe("representative names", () => {
        const named = [
            scoreRow(1, 12, 8, "MD", ["Jane Doe"]),
            scoreRow(2, 3, 4, "MD", ["Amy Adams", "Zed Zane"]),
            scoreRow(3, 9, 1, "MD", []),
        ];

        test("a district with one representative says so on its row", () => {
            wrap(panel(named));

            expect(screen.getByTestId("district-votes-names-1")).toHaveTextContent("Representative: Jane Doe");
        });

        test("a district with several representatives joins the names with commas under the plural", () => {
            wrap(panel(named));

            expect(screen.getByTestId("district-votes-names-2")).toHaveTextContent(
                "Representatives: Amy Adams, Zed Zane",
            );
        });

        test("a district with nobody in office keeps only its label", () => {
            wrap(panel(named));

            expect(screen.getByTestId("district-votes-row-3")).toBeTruthy();
            expect(screen.queryByTestId("district-votes-names-3")).toBeNull();
            expect(within(screen.getByTestId("district-votes-row-3")).queryByText(/Representative/)).toBeNull();
        });

        test("a response that carries no names draws no names line and speaks the unchanged chart summary", () => {
            wrap(panel(scores));

            expect(screen.queryByText(/Representative/)).toBeNull();
            expect(screen.getByTestId("district-votes-chart").props.accessibilityLabel).toBe(
                "Votes by district. District 1: 60 percent for, 40 percent against. District 2: 43 percent for, 57 percent against. District 3: 90 percent for, 10 percent against.",
            );
        });

        test.each([[null], ["Jane Doe"], [[""]], [[" "]], [[null, 4]]])(
            "a names value of %j that is not a list of names draws no names line",
            (legislatorNames) => {
                const row = { ...scoreRow(1, 4, 2), legislator_names: legislatorNames } as unknown as ReturnType<
                    typeof scoreRow
                >;
                wrap(panel([row]));

                expect(screen.queryByTestId("district-votes-names-1")).toBeNull();
            },
        );

        test("the by-district chart reads each district's names aloud, and the net chart summary is unchanged", () => {
            wrap(panel(named, [READER]));

            expect(screen.getByTestId("district-votes-chart").props.accessibilityLabel).toBe(
                "Votes by district. District 1 (Representative: Jane Doe): 60 percent for, 40 percent against. District 2 (Representatives: Amy Adams, Zed Zane): 43 percent for, 57 percent against. District 3, your district: 90 percent for, 10 percent against.",
            );
            expect(screen.getByTestId("district-affinity-chart").props.accessibilityLabel).toBe(
                "Net lean by district, percent for minus percent against. District 1: plus 20 points. District 2: minus 14 points. District 3, your district: plus 80 points.",
            );
        });

        test("names appear once per district, in the by-district chart only", () => {
            wrap(panel(named));

            expect(screen.getAllByText("Representative: Jane Doe")).toHaveLength(1);
            expect(screen.queryByTestId("district-affinity-names-1")).toBeNull();
        });

        test("the names sit in the bar column, so the label and count columns keep their widths", () => {
            wrap(panel(named));

            const bars = screen.getByTestId("district-votes-bars-1");
            expect(within(bars).getByTestId("district-votes-names-1")).toBeTruthy();
            expect(within(bars).getByText("60%")).toBeTruthy();
            expect(styleOf(within(screen.getByTestId("district-votes-row-1")).getByText("District 1")).minWidth).toBe(
                72,
            );
            expect(styleOf(within(bars).getByText("60%")).minWidth).toBe(52);
        });

        test("a long list of names wraps to two lines and ends in an ellipsis instead of growing the row", () => {
            const longNames = [
                "Alexandria Ocasio-Cortez-Washington",
                "Bartholomew Featherstonehaugh",
                "Cornelius Vanderbilt",
            ];
            wrap(panel([scoreRow(1, 12, 8, "MD", longNames)]));

            const names = screen.getByTestId("district-votes-names-1");
            expect(names).toHaveTextContent(`Representatives: ${longNames.join(", ")}`);
            expect(names.props.numberOfLines).toBe(2);
            expect(names.props.ellipsizeMode).toBe("tail");
            expect(styleOf(names).width).toBeUndefined();
        });

        test("eight districts with names still fold at eight rows and name every shown district", () => {
            const many = Array.from({ length: 12 }, (_, i) => scoreRow(i + 1, i + 1, 1, "MD", [`Member ${i + 1}`]));
            wrap(panel(many));

            for (let number = 1; number <= 8; number++) {
                expect(screen.getByTestId(`district-votes-names-${number}`)).toHaveTextContent(
                    `Representative: Member ${number}`,
                );
            }
            expect(screen.queryByTestId("district-votes-names-9")).toBeNull();
            expect(screen.getByTestId("district-votes-chart").props.accessibilityLabel).toContain(
                "4 more districts are not shown.",
            );
        });

        test("the names line is muted text with a dark-mode colour, like the other secondary text", () => {
            wrap(panel(named));

            const className = String(screen.getByTestId("district-votes-names-1").props.className);
            expect(className).toContain("text-muted-foreground-light");
            expect(className).toContain("dark:text-muted-foreground-dark");
        });
    });

    describe("a long list of districts", () => {
        const many = Array.from({ length: 12 }, (_, i) => scoreRow(i + 1, i + 1, 1));

        test("caps at eight with a control to show all", () => {
            wrap(panel(many));

            expect(screen.getAllByText("District 8").length).toBeGreaterThan(0);
            expect(screen.queryByText("District 9")).toBeNull();
            expect(screen.getByText("Show all 12 districts")).toBeTruthy();
            expect(screen.getByTestId("district-votes-chart").props.accessibilityLabel).toContain(
                "4 more districts are not shown.",
            );
        });

        test("expands to every district and collapses again", () => {
            wrap(panel(many));

            fireEvent.press(screen.getByTestId("district-votes-toggle"));
            expect(screen.getAllByText("District 12").length).toBeGreaterThan(0);
            expect(screen.getByText("Show fewer districts")).toBeTruthy();
            expect(screen.getByTestId("district-votes-toggle").props.accessibilityState).toEqual(
                expect.objectContaining({ expanded: true }),
            );

            fireEvent.press(screen.getByTestId("district-votes-toggle"));
            expect(screen.queryByText("District 12")).toBeNull();
        });

        test("keeps the reader's district in the lists even when it falls past the cap", () => {
            wrap(panel(many, [{ name: "MD11", number: 11, region_code: "MD" }]));

            expect(screen.getAllByText("District 11").length).toBeGreaterThan(0);
            expect(screen.getByTestId("district-votes-row-11")).toBeTruthy();
            expect(screen.queryByTestId("district-votes-row-10")).toBeNull();
        });

        test("has no control for eight districts or fewer", () => {
            wrap(panel(many.slice(0, 8)));
            expect(screen.queryByTestId("district-votes-toggle")).toBeNull();
        });

        test("keeps the control outside the accessible chart groups, so it stays reachable", () => {
            wrap(panel(many));
            const toggle = screen.getByTestId("district-votes-toggle");
            let node = toggle.parent;
            while (node) {
                if (node.props?.testID !== "district-votes-toggle") {
                    expect(node.props?.accessible).not.toBe(true);
                }
                node = node.parent;
            }
        });
    });
});
