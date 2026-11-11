// Combobox draws through a Radix Popover, invisible to these tests (already covered by
// combobox.test.ts), so only Combobox is stubbed — filterComboboxOptions and
// BillPickerSortToggle stay real.

import { describe, expect, it, vi, afterEach } from "vitest";
import { cleanup, fireEvent, render as rtlRender, screen } from "@testing-library/react";
import { cloneElement, type ReactElement } from "react";
import type { ComboboxOption } from "app/frontend/components/ui/combobox";
import { sway } from "sway";
import { ETab } from "app/frontend/components/bill/creator/constants";

const { comboboxSpy, routerGetMock } = vi.hoisted(() => ({
    comboboxSpy: vi.fn<(props: Record<string, unknown>) => void>(),
    routerGetMock: vi.fn<(url: string, data: Record<string, never>, options: Record<string, unknown>) => void>(),
}));

vi.mock("app/frontend/components/ui/combobox", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/components/ui/combobox")>();
    return {
        ...actual,
        Combobox: (props: Record<string, unknown>) => {
            comboboxSpy(props);
            return <div data-testid={props["data-testid"] as string} />;
        },
    };
});

vi.mock("@inertiajs/react", async (importOriginal) => {
    const actual = await importOriginal<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        router: {
            get: (url: string, data: Record<string, never>, options: Record<string, unknown>) => {
                routerGetMock(url, data, options);
                window.history.replaceState({}, "", url);
            },
        },
    };
});

import BillCreatorPicker from "app/frontend/components/admin/creator/BillCreatorPicker";

let rerenderPicker: (() => void) | undefined;

const render = (element: ReactElement) => {
    const view = rtlRender(element);
    rerenderPicker = () => view.rerender(cloneElement(element));
    return view;
};

const selectSort = (testId: string) => {
    fireEvent.click(screen.getByTestId(testId));
    rerenderPicker?.();
};

afterEach(() => {
    cleanup();
    rerenderPicker = undefined;
    routerGetMock.mockReset();
    window.history.replaceState({}, "", "/");
});

const bill = (overrides: Partial<sway.IBillPickerOption>): sway.IBillPickerOption => ({
    id: 1,
    external_id: "CB001",
    title: "Untitled",
    scheduled_release_date_utc: null,
    status: null,
    chamber: "council",
    category: "Ordinance",
    introduced_date_time_utc: null,
    latest_action_date_time_utc: null,
    sponsor_name: "",
    legislator_vote_count: 0,
    organization_position_count: 0,
    interesting_badges: [],
    interesting_score_normalized: null,
    ...overrides,
});

interface ISpiedComboboxProps {
    options: ComboboxOption[];
    pinnedOption?: ComboboxOption;
    "data-testid"?: string;
}

const lastComboboxProps = () => comboboxSpy.mock.calls.at(-1)?.[0] as unknown as ISpiedComboboxProps;

describe("BillCreatorPicker sort toggle", () => {
    it("defaults to Newest order (original array order)", () => {
        const bills = [
            bill({ id: 1, external_id: "B", title: "Beta Bill" }),
            bill({ id: 2, external_id: "A", title: "Alpha Bill" }),
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        expect(screen.getByTestId("sort-newest").getAttribute("aria-pressed")).toBe("true");
        const { options } = lastComboboxProps();
        expect(options.map((o) => o.value)).toEqual(["1", "2"]);
    });

    // @lat: [[bill-creator-shell#The Bill Creator shell#Why the picker sort stays in the address]]
    it("reads a valid pasted sort from the address and defaults invalid values to Newest", () => {
        const bills = [
            bill({ id: 1, external_id: "A", title: "Alpha Bill", interesting_score_normalized: 0.2 }),
            bill({ id: 2, external_id: "B", title: "Beta Bill", interesting_score_normalized: 0.9 }),
        ];
        window.history.replaceState({}, "", "/admin/bill_creator/new?bill_creator_tab=summary&bill_creator_sort=score");
        const props = {
            tabKey: ETab.Creator,
            bills,
            currentBillId: null,
            onValueChange: vi.fn<(value: string) => void>(),
        };
        const view = render(<BillCreatorPicker {...props} />);

        expect(screen.getByTestId("sort-score").getAttribute("aria-pressed")).toBe("true");
        expect(lastComboboxProps().options.map((option) => option.value)).toEqual(["2", "1"]);

        window.history.replaceState({}, "", "/admin/bill_creator/new?bill_creator_sort=unknown");
        view.rerender(<BillCreatorPicker {...props} />);

        expect(screen.getByTestId("sort-newest").getAttribute("aria-pressed")).toBe("true");
        expect(lastComboboxProps().options.map((option) => option.value)).toEqual(["1", "2"]);
    });

    // @lat: [[bill-creator-shell#The Bill Creator shell#Why the picker sort stays in the address]]
    it("writes the selected sort through Inertia while preserving other address state", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/new?bill_creator_tab=summary&run_id=77");
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={[]}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        selectSort("sort-score");

        expect(routerGetMock).toHaveBeenCalledTimes(1);
        const [url, data, options] = routerGetMock.mock.calls[0] ?? [];
        expect(url).toBe("/admin/bill_creator/new?bill_creator_tab=summary&run_id=77&bill_creator_sort=score");
        expect(data).toEqual({});
        expect(options).toMatchObject({ only: ["bills"], preserveScroll: true, preserveState: true });

        selectSort("sort-newest");

        expect(screen.getByTestId("sort-newest").getAttribute("aria-pressed")).toBe("true");
        expect(routerGetMock.mock.calls[1]?.[0]).toBe(
            "/admin/bill_creator/new?bill_creator_tab=summary&run_id=77&bill_creator_sort=",
        );
    });

    it("toggling to A-Z sorts alphabetically by label", () => {
        const bills = [
            bill({ id: 1, external_id: "Z", title: "Zeta Bill" }),
            bill({ id: 2, external_id: "A", title: "Alpha Bill" }),
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        selectSort("sort-alpha");

        expect(window.location.search).toContain("bill_creator_sort=alpha");
        expect(screen.getByTestId("sort-alpha").getAttribute("aria-pressed")).toBe("true");
        const { options } = lastComboboxProps();
        expect(options.map((o) => o.value)).toEqual(["2", "1"]);
    });

    it("toggling to Most Interesting reorders by interesting_score_normalized descending, null last", () => {
        const bills = [
            bill({ id: 1, external_id: "A", title: "Alpha Bill", interesting_score_normalized: 0.2 }),
            bill({ id: 2, external_id: "B", title: "Beta Bill", interesting_score_normalized: 0.9 }),
            bill({ id: 3, external_id: "C", title: "Gamma Bill", interesting_score_normalized: null }),
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        selectSort("sort-score");

        expect(screen.getByTestId("sort-score").getAttribute("aria-pressed")).toBe("true");
        const { options } = lastComboboxProps();
        expect(options.map((o) => o.value)).toEqual(["2", "1", "3"]);
    });

    it("sorts Recent intro/vote newest first and places bills without those dates last", () => {
        const bills = [
            {
                ...bill({ id: 1, external_id: "Z", title: "Zeta Bill" }),
                latest_action_date_time_utc: "2026-06-01T00:00:00Z",
            },
            { ...bill({ id: 2, external_id: "A", title: "Alpha Bill" }), latest_action_date_time_utc: null },
            {
                ...bill({ id: 3, external_id: "B", title: "Beta Bill" }),
                latest_action_date_time_utc: "2026-06-03T00:00:00Z",
            },
            {
                ...bill({ id: 4, external_id: "G", title: "Gamma Bill" }),
                latest_action_date_time_utc: "2026-05-31T00:00:00Z",
            },
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        selectSort("sort-latest-action");

        expect(screen.getByTestId("sort-latest-action").getAttribute("aria-pressed")).toBe("true");
        expect(lastComboboxProps().options.map((option) => option.value)).toEqual(["3", "1", "4", "2"]);

        selectSort("sort-alpha");
        expect(lastComboboxProps().options.map((option) => option.value)).toEqual(["2", "3", "4", "1"]);
    });

    it("breaks score ties alphabetically by label instead of server row order (IN-04)", () => {
        // Deliberately not in alphabetical order as the server sends them: two
        // with no score, which count as -1, and two both scoring 0.5.
        const bills = [
            bill({ id: 1, external_id: "D", title: "Delta Bill", interesting_score_normalized: null }),
            bill({ id: 2, external_id: "B", title: "Beta Bill", interesting_score_normalized: 0.5 }),
            bill({ id: 3, external_id: "C", title: "Gamma Bill", interesting_score_normalized: null }),
            bill({ id: 4, external_id: "A", title: "Alpha Bill", interesting_score_normalized: 0.5 }),
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        selectSort("sort-score");

        const { options } = lastComboboxProps();
        // Tied at 0.5: "A — Alpha Bill" comes before "B — Beta Bill". Both
        // unscored: "C — Gamma Bill" comes before "D — Delta Bill".
        expect(options.map((o) => o.value)).toEqual(["4", "2", "3", "1"]);
    });

    it("returns array order in Newest mode and sorts case-insensitively in the score-mode tiebreaker (IN-04)", () => {
        // Lodash compares raw characters, which puts every capital letter ahead
        // of every lowercase one, so the lowercase "b" entry would land AFTER
        // "Zeta" if the labels were not lowercased first.
        const bills = [
            bill({ id: 1, external_id: "Z", title: "Zeta Bill", interesting_score_normalized: 0.5 }),
            bill({ id: 2, external_id: "b", title: "beta lowercase bill", interesting_score_normalized: 0.5 }),
            bill({ id: 3, external_id: "A", title: "Alpha Bill", interesting_score_normalized: 0.5 }),
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        // Newest mode preserves the original array order.
        expect(lastComboboxProps().options.map((o) => o.value)).toEqual(["1", "2", "3"]);

        // In score mode all three tie at 0.5, so the tiebreaker has to give the
        // same order, ignoring capitals.
        selectSort("sort-score");
        expect(lastComboboxProps().options.map((o) => o.value)).toEqual(["3", "2", "1"]);
    });

    it("toggling back to Newest restores array order", () => {
        const bills = [
            bill({ id: 1, external_id: "A", title: "Alpha Bill", interesting_score_normalized: 0.2 }),
            bill({ id: 2, external_id: "B", title: "Beta Bill", interesting_score_normalized: 0.9 }),
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        selectSort("sort-score");
        selectSort("sort-newest");

        const { options } = lastComboboxProps();
        expect(options.map((o) => o.value)).toEqual(["1", "2"]);
    });

    it("type-to-filter (via the shared filterComboboxOptions) narrows correctly in both sort modes", async () => {
        const { filterComboboxOptions } = await vi.importActual<
            typeof import("app/frontend/components/ui/combobox-filter")
        >("@/components/ui/combobox-filter");
        const bills = [
            bill({ id: 1, external_id: "A", title: "Alpha Bill", interesting_score_normalized: 0.2 }),
            bill({ id: 2, external_id: "B", title: "Beta Bill", interesting_score_normalized: 0.9 }),
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        const alphaOptions = lastComboboxProps().options;
        expect(filterComboboxOptions(alphaOptions, "beta").map((o) => o.value)).toEqual(["2"]);

        selectSort("sort-score");
        const scoreOptions = lastComboboxProps().options;
        expect(filterComboboxOptions(scoreOptions, "alpha").map((o) => o.value)).toEqual(["1"]);
    });

    it("keeps the New/All sentinel pinned and unaffected by sort mode", () => {
        const bills = [bill({ id: 1, external_id: "A", title: "Alpha Bill" })];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        expect(lastComboboxProps().pinnedOption).toEqual({ value: "__new__", label: "New Bill" });

        selectSort("sort-score");

        expect(lastComboboxProps().pinnedOption).toEqual({ value: "__new__", label: "New Bill" });
    });

    it("preserves the existing data-testid=bill-creator-picker on the underlying Combobox", () => {
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={[]}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        expect(screen.getByTestId("bill-creator-picker")).toBeTruthy();
        expect(lastComboboxProps()["data-testid"]).toBe("bill-creator-picker");
    });
});

// @lat: [[bill-interesting-score#The bill interesting score#Why the picker keeps search and navigation separate]]
describe("BillCreatorPicker subject-matter search", () => {
    // The real filter, not the mocked Combobox above — loaded once here since the module
    // mock replaces the component and these tests are about the pure function.
    const loadFilter = async () => {
        const actual = await vi.importActual<typeof import("app/frontend/components/ui/combobox-filter")>(
            "@/components/ui/combobox-filter",
        );
        return actual.filterComboboxOptions;
    };

    const HENDLER =
        "Baltimore City Landmark List FOR the purpose of designating the Hendler Creamery building " +
        "as a historical landmark";

    it("finds a bill by a word that sits after the FOR-the-purpose-of clause", async () => {
        const filterComboboxOptions = await loadFilter();
        const bills = [
            bill({ id: 1, external_id: "23-0394", title: HENDLER }),
            bill({ id: 2, external_id: "23-0100", title: "Sale of Property" }),
        ];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        const { options } = lastComboboxProps();

        expect(filterComboboxOptions(options, "hendler").map((o) => o.value)).toEqual(["1"]);
        expect(filterComboboxOptions(options, "creamery").map((o) => o.value)).toEqual(["1"]);
    });

    // The clause is dropped from what is DRAWN, which is the change that made
    // the label short. Searching and labelling are the two halves, and only one
    // of them was meant to lose the clause.
    it("keeps the shortened title on the label the closed box draws", () => {
        const bills = [bill({ id: 1, external_id: "23-0394", title: HENDLER })];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        expect(lastComboboxProps().options[0].label).toBe("23-0394 — Baltimore City Landmark List");
    });

    it("still finds a bill by its number and by a sponsor the label never shows", async () => {
        const filterComboboxOptions = await loadFilter();
        const bills = [bill({ id: 1, external_id: "23-0394", title: HENDLER, sponsor_name: "Odette Ramos" })];
        render(
            <BillCreatorPicker
                tabKey={ETab.Creator}
                bills={bills}
                currentBillId={null}
                onValueChange={vi.fn<(value: string) => void>()}
            />,
        );

        const { options } = lastComboboxProps();

        expect(filterComboboxOptions(options, "23-0394").map((o) => o.value)).toEqual(["1"]);
        expect(filterComboboxOptions(options, "ramos").map((o) => o.value)).toEqual(["1"]);
    });
});
