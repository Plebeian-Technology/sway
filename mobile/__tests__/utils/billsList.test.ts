/**
 // @lat: [[bills-controller-design#Why the search and sort labels in parityCopy.ts note the underlying split]]
 */
import { deriveVisibleBills, DEFAULT_BILLS_SORT, type BillsSortValue } from "../../src/utils/billsList";

type Fixture = { id: number; title: string; introduced_date_time_utc?: string; categories?: string[] };

const bill = (id: number, title: string, introduced?: string, categories?: string[]): Fixture => ({
    id,
    title,
    ...(introduced ? { introduced_date_time_utc: introduced } : {}),
    ...(categories ? { categories } : {}),
});

// @lat: [[bills-controller-design#Why the search and sort labels in parityCopy.ts note the underlying split]]
const HOUSING = bill(1, "Housing Trust Fund", "2026-01-05T00:00:00Z", ["Housing"]);
const POLICE = bill(2, "Police Accountability", "2026-03-01T00:00:00Z", ["Police"]);
const MUSEUM = bill(3, "Art Museum Employees", "2026-02-10T00:00:00Z", ["Budget & Taxes", "Labor & Employment"]);
const UNDATED = bill(4, "Zoning Variance"); // no date, no categories

const ALL = [HOUSING, POLICE, MUSEUM, UNDATED];

const derive = (overrides: Partial<{ categories: string[]; search: string; sort: BillsSortValue }> = {}) =>
    deriveVisibleBills(ALL, { categories: [], search: "", sort: DEFAULT_BILLS_SORT, ...overrides }).map((b) => b.id);

describe("deriveVisibleBills", () => {
    test("default sort: newest introduced first, undated last (NULL-as-smallest)", () => {
        expect(derive()).toEqual([2, 3, 1, 4]);
    });

    test("oldest first: undated sorts FIRST — mirrors SQLite NULLs-smallest asc", () => {
        expect(derive({ sort: "introduced_date_time_utc:asc" })).toEqual([4, 1, 3, 2]);
    });

    test("title A–Z and Z–A", () => {
        expect(derive({ sort: "title:asc" })).toEqual([3, 1, 2, 4]);
        expect(derive({ sort: "title:desc" })).toEqual([4, 2, 1, 3]);
    });

    test("equal sort keys tiebreak on id desc (mirrors the server's :id => :desc)", () => {
        const sameDay = [bill(10, "Alpha", "2026-04-01T00:00:00Z"), bill(11, "Beta", "2026-04-01T00:00:00Z")];
        const ids = deriveVisibleBills(sameDay, {
            categories: [],
            search: "",
            sort: DEFAULT_BILLS_SORT,
        }).map((b) => b.id);
        expect(ids).toEqual([11, 10]);
    });

    test("search: case-insensitive title substring, trimmed", () => {
        expect(derive({ search: "POLICE" })).toEqual([2]);
        expect(derive({ search: "  museum  " })).toEqual([3]);
        expect(derive({ search: "no-such-bill" })).toEqual([]);
    });

    test("category OR-intersection (D-04): union across chips, no-category bills hidden", () => {
        expect(derive({ categories: ["Housing", "Police"] })).toEqual([2, 1]);
        expect(derive({ categories: ["Labor & Employment"] })).toEqual([3]);
    });

    test("search and categories compose (AND across filter kinds)", () => {
        expect(derive({ categories: ["Housing", "Police"], search: "housing" })).toEqual([1]);
    });

    test("does not mutate the input array", () => {
        const input = [...ALL];
        deriveVisibleBills(input, { categories: [], search: "", sort: "title:asc" });
        expect(input.map((b) => b.id)).toEqual([1, 2, 3, 4]);
    });
});
