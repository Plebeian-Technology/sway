// @lat: [[bills-controller-design#Why mobile deriveVisibleBills mirrors server sort semantics exactly]]
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export type BillsSortValue = (typeof PARITY_COPY.bills.sortOptions)[number]["value"];
export const DEFAULT_BILLS_SORT: BillsSortValue = "introduced_date_time_utc:desc";

export interface VisibleBillsFilters {
    categories: string[];
    search: string;
    sort: BillsSortValue;
}

type BillLike = { id: number } & Record<string, unknown>;

export function deriveVisibleBills<T extends BillLike>(bills: readonly T[], filters: VisibleBillsFilters): T[] {
    const term = filters.search.trim().toLowerCase();

    const filtered = bills.filter((bill) => {
        const billCategories = bill.categories as string[] | undefined;
        const inCategory =
            !filters.categories.length || (billCategories?.some((c) => filters.categories.includes(c)) ?? false);
        if (!inCategory) return false;
        return (
            !term ||
            String(bill.title ?? "")
                .toLowerCase()
                .includes(term)
        );
    });

    const [column, direction] = filters.sort.split(":");
    const sign = direction === "asc" ? 1 : -1;
    return [...filtered].sort((a, b) => {
        const av = String(a[column] ?? "");
        const bv = String(b[column] ?? "");
        if (av !== bv) {
            const base = column === "title" ? av.localeCompare(bv) : av < bv ? -1 : 1;
            return sign * base;
        }
        return b.id - a.id;
    });
}
