// @lat: [[bill-category-tags-design#BillCategoryTags.tsx]]

import { describe, expect, it } from "vitest";

import { renderV2 } from "app/frontend/__tests__/test-utils";
import BillCategoryTags from "app/frontend/components/bill/BillCategoryTags";

describe("BillCategoryTags", () => {
    it("renders each active category name verbatim", () => {
        const { queryByText } = renderV2(<BillCategoryTags categories={["Civil Rights", "Budget & Taxes"]} />);

        expect(queryByText("Civil Rights")).not.toBeNull();
        // The name with an ampersand must come through untouched, which proves
        // nothing here re-capitalises the names.
        expect(queryByText("Budget & Taxes")).not.toBeNull();
    });

    it("renders nothing when the bill has no categories", () => {
        const { container } = renderV2(<BillCategoryTags categories={[]} />);
        expect(container.textContent).toBe("");
    });

    it("renders nothing when categories is undefined", () => {
        const { container } = renderV2(<BillCategoryTags categories={undefined} />);
        expect(container.textContent).toBe("");
    });
});
