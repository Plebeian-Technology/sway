// @lat: [[organization-affiliation-labels#Organization affiliation labels#Every position carries its own tag]]
import { PARITY_COPY } from "../sway_constants/parityCopy";

export type OrganizationPositionSourceKind =
    | "hearing_testimony"
    | "news_article"
    | "sway_admin"
    | "organization"
    | null;

export const organizationPositionTag = (
    organizationName: string,
    sourceKind: OrganizationPositionSourceKind | undefined,
): string =>
    sourceKind === "organization" ? PARITY_COPY.orgs.postedBy(organizationName) : PARITY_COPY.orgs.compiledBySway;

// @lat: [[organization-affiliation-labels#Organization affiliation labels#A compiled position names its source]]
export const organizationPositionSourceLabel = (
    sourceKind: OrganizationPositionSourceKind | undefined,
): string | undefined => {
    if (sourceKind === "hearing_testimony") return PARITY_COPY.orgs.sourceHearingTestimony;
    if (sourceKind === "news_article") return PARITY_COPY.orgs.sourceNewsArticle;
    return undefined;
};
