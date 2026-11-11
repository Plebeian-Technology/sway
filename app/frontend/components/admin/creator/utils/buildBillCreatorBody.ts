import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { sway } from "sway";

const optionValue = (raw: unknown): string | undefined =>
    typeof raw === "string" ? raw : (raw as { value?: string } | null)?.value;

export function buildBillCreatorBody(
    rawData: IApiBillCreator,
    summary: string,
    swayLocaleId: number,
    newsUsage: "none" | "cited" = "none",
): IApiBillCreator {
    return {
        ...rawData,
        summary,
        news_usage: rawData.news_usage ?? newsUsage,
        status: optionValue(rawData.status) as sway.TBillStatus,
        // @lat: [[jurisdiction-rules-design#useNewBillInitialValues's chamber default]]
        chamber: (optionValue(rawData.chamber) ?? "") as sway.TBillChamber,
        legislator_id: (typeof rawData.legislator_id === "string" && rawData.legislator_id !== ""
            ? Number(rawData.legislator_id)
            : ((rawData.legislator_id as { value?: number } | null)?.value ?? rawData.legislator_id)) as number,
        sway_locale_id: swayLocaleId,
    };
}
