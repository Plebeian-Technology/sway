import { notify } from "app/frontend/sway_utils";

// @lat: [[notify-server-refusal-pattern#Why notifyServerRefusal prefers the server's wording, with a fallback]]

// @lat: [[refusal-key-catalog#Why a fixed union instead of string]]
export type TRefusalKey =
    | "org_position"
    | "generation"
    | "legislator_votes"
    | "pipeline"
    | "testimony_coverage"
    | "campaign_position"
    | "campaign_organization"
    | "sending_service";

// @lat: [[notify-server-refusal-pattern#Why serverRefusalMessage checks the shape carefully]]
export const serverRefusalMessage = (errors: unknown, key: TRefusalKey): string | undefined => {
    const copy = (errors as Record<string, unknown> | null | undefined)?.[key];
    if (typeof copy !== "string") return undefined;

    return copy.trim().length > 0 ? copy : undefined;
};

// @lat: [[notify-server-refusal-pattern#Why notifyServerRefusal prefers the server's wording, with a fallback]]
export const notifyServerRefusal = (errors: unknown, key: TRefusalKey, fallback: string): void => {
    notify({ level: "error", title: serverRefusalMessage(errors, key) ?? fallback });
};

// @lat: [[private-individual-guard-override]]
export const isPrivateIndividualRefusal = (errors: unknown): boolean =>
    (errors as Record<string, unknown> | null | undefined)?.private_individual_refusal === true;
