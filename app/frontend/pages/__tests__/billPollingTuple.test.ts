// @lat: [[client-caches-and-identity#Bill refresh feedback]]

import { describe, expect, it } from "vitest";
import billSource from "app/frontend/pages/Bill.tsx?raw";
import botmSource from "app/frontend/pages/BillOfTheMonth.tsx?raw";

const pollingTuple = (source: string): string => {
    const match = source.match(/const POLLING_PROPS\s*=\s*(\[[^\]]*\])/);
    return match ? match[1] : "";
};

describe("Bill / BillOfTheMonth POLLING_PROPS tuple", () => {
    it.each([
        ["Bill.tsx", billSource],
        ["BillOfTheMonth.tsx", botmSource],
    ])("%s POLLING_PROPS includes bill_score and organizations", (_name, source) => {
        const tuple = pollingTuple(source);
        expect(tuple).toContain('"bill_score"');
        expect(tuple).toContain('"organizations"');
    });
});
