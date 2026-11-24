import { describe, expect, it } from "vitest";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import {
    organizationPositionSourceLabel,
    organizationPositionTag,
} from "app/frontend/sway_utils/organizationPositionLabels";

describe("organizationPositionTag", () => {
    it("says the organization posted a position its members wrote", () => {
        expect(organizationPositionTag("Bikemore", "organization")).toBe("Posted by Bikemore");
    });

    it.each(["hearing_testimony", "news_article", "sway_admin", null, undefined] as const)(
        "says Sway compiled a %s position",
        (sourceKind) => {
            expect(organizationPositionTag("Bikemore", sourceKind)).toBe(PARITY_COPY.orgs.compiledBySway);
        },
    );
});

describe("organizationPositionSourceLabel", () => {
    it("labels testimony and news sources", () => {
        expect(organizationPositionSourceLabel("hearing_testimony")).toBe(PARITY_COPY.orgs.sourceHearingTestimony);
        expect(organizationPositionSourceLabel("news_article")).toBe(PARITY_COPY.orgs.sourceNewsArticle);
    });

    it.each(["organization", "sway_admin", null, undefined] as const)("gives no label for %s", (sourceKind) => {
        expect(organizationPositionSourceLabel(sourceKind)).toBeUndefined();
    });
});
