export type SupportTone = "success" | "danger" | "neutral";

export const supportTone = (support: string | null | undefined): SupportTone => {
    if (support === "FOR") return "success";
    if (support === "AGAINST") return "danger";
    return "neutral";
};
