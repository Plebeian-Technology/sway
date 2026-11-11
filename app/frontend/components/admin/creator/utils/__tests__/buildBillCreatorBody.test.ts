import { describe, expect, it } from "vitest";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { buildBillCreatorBody } from "app/frontend/components/admin/creator/utils/buildBillCreatorBody";

const rawData = (overrides: Record<string, unknown> = {}): IApiBillCreator =>
    ({
        external_id: "B-1",
        title: "A bill",
        status: "committee",
        chamber: "house",
        legislator_id: "7",
        summary: "stale summary",
        ...overrides,
    }) as unknown as IApiBillCreator;

describe("buildBillCreatorBody", () => {
    it("applies the summary argument, overriding rawData.summary", () => {
        expect(buildBillCreatorBody(rawData(), "fresh summary", 3).summary).toBe("fresh summary");
    });

    it("stamps the sway locale id", () => {
        expect(buildBillCreatorBody(rawData(), "", 42).sway_locale_id).toBe(42);
    });

    it("passes through plain-string select fields", () => {
        const body = buildBillCreatorBody(rawData({ status: "passed", chamber: "senate" }), "", 1);
        expect(body.status).toBe("passed");
        expect(body.chamber).toBe("senate");
    });

    it("unwraps {value} option objects for select fields", () => {
        const body = buildBillCreatorBody(
            rawData({
                status: { value: "vetoed" },
                chamber: { value: "house" },
            }),
            "",
            1,
        );
        expect(body.status).toBe("vetoed");
        expect(body.chamber).toBe("house");
    });

    // @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
    it("leaves an empty chamber empty, so the required-field check can refuse it", () => {
        expect(buildBillCreatorBody(rawData({ chamber: "" }), "", 1).chamber).toBe("");
    });

    it("coerces a numeric-string legislator_id to a number", () => {
        expect(buildBillCreatorBody(rawData({ legislator_id: "7" }), "", 1).legislator_id).toBe(7);
    });

    it("unwraps a {value} legislator_id option object", () => {
        expect(buildBillCreatorBody(rawData({ legislator_id: { value: 9 } }), "", 1).legislator_id).toBe(9);
    });

    it("preserves unrelated raw fields", () => {
        const body = buildBillCreatorBody(rawData({ external_id: "HB-99", title: "Keep me" }), "", 1);
        expect(body.external_id).toBe("HB-99");
        expect(body.title).toBe("Keep me");
    });
});
