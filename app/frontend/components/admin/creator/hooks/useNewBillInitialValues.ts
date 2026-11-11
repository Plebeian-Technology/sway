/* oxlint-disable react-hooks/exhaustive-deps */

import { notify, SWAY_STORAGE, toSelectOption } from "app/frontend/sway_utils";
import { useEffect, useMemo, useState } from "react";
import { sway } from "sway";

import { usePage } from "@inertiajs/react";
import { reconciledDraftSummary } from "app/frontend/components/admin/creator/billDraftSummaryProvenance";
import { asBillStatus } from "app/frontend/components/admin/creator/billStatus";
import { asStoredBillDraft } from "app/frontend/components/admin/creator/storedBillDraft";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useSwayLocale } from "app/frontend/hooks/useSwayLocales";

interface IPageProps {
    // @lat: [[bill-creator-initial-values-and-draft-restore#Why bill is optional on the page props]]
    bill?: sway.IBill;
    legislators: sway.ILegislator[];
    organizations: sway.IOrganization[];
    [key: string]: unknown;
}

interface IDraftRestore {
    values: IApiBillCreator | null;
    yielded: boolean;
}

export const useNewBillInitialValues = (): IApiBillCreator => {
    const [locale] = useSwayLocale();
    const { props } = usePage<IPageProps>();
    const bill = props.bill;

    // @lat: [[bill-creator-initial-values-and-draft-restore#Why the return type annotation goes on the callback, not on useMemo's argument]]
    const initialBill = useMemo(
        (): IApiBillCreator => ({
            id: bill?.id,
            external_id: bill?.external_id?.trim() || "",
            external_version: bill?.external_version?.trim() || "",
            title: bill?.title?.trim() || "",
            link: bill?.link?.trim() || "",
            legislator_id: bill?.legislator_id || null,
            // @lat: [[jurisdiction-rules-design#useNewBillInitialValues's chamber default]]
            chamber:
                bill?.chamber ||
                (locale?.default_bill_chamber
                    ? toSelectOption(locale.default_bill_chamber, locale.default_bill_chamber)
                    : null),
            summary: bill?.summary?.trim() ?? "",
            // @lat: [[bill-creator-initial-values-and-draft-restore#Why status is narrowed rather than trimmed]]
            status: asBillStatus(bill?.status) ?? "committee",
            active: typeof bill?.active === "boolean" ? bill.active : true,

            introduced_date_time_utc: bill?.introduced_date_time_utc ? new Date(bill?.introduced_date_time_utc) : null,
            withdrawn_date_time_utc: bill?.withdrawn_date_time_utc ? new Date(bill?.withdrawn_date_time_utc) : null,
            house_vote_date_time_utc: bill?.house_vote_date_time_utc ? new Date(bill?.house_vote_date_time_utc) : null,
            senate_vote_date_time_utc: bill?.senate_vote_date_time_utc
                ? new Date(bill?.senate_vote_date_time_utc)
                : null,

            // @lat: [[use-locale-hook-contract#swayLocaleId in the Bill Creator form]]
            sway_locale_id: locale?.id ?? bill?.sway_locale_id,

            audio_bucket_path: bill?.audio_bucket_path?.trim() || "",
            audio_by_line: bill?.audio_by_line?.trim() || "",

            house_roll_call_vote_number: bill?.vote?.house_roll_call_vote_number ?? "",
            senate_roll_call_vote_number: bill?.vote?.senate_roll_call_vote_number ?? "",
        }),
        [bill, locale],
    );

    // @lat: [[temp-bill-storage-peek-parsing#The restore runs once in useNewBillInitialValues]]
    const [restore] = useState<IDraftRestore>(() => {
        // @lat: [[bill-creator-initial-values-and-draft-restore#Why the stored draft is scoped to the bill it was taken against]]
        const stored = asStoredBillDraft(new TempBillStorage(SWAY_STORAGE.Local.BillCreator.Bill).peek());
        const storedBillId = stored?.id && stored.id > 0 ? stored.id : 0;
        const currentBillId = bill?.id && bill.id > 0 ? bill.id : 0;
        if (!stored || storedBillId !== currentBillId) return { values: null, yielded: false };

        // @lat: [[bill-creator-initial-values-and-draft-restore#Why the draft's summary yields to a newer published one]]
        const reconciled = reconciledDraftSummary(stored, initialBill.summary);
        // @lat: [[bill-creator-initial-values-and-draft-restore#Why the stored draft is scoped to the bill it was taken against]]
        return { values: { ...initialBill, ...stored, ...reconciled.values }, yielded: reconciled.yielded };
    });

    // @lat: [[temp-bill-storage-peek-parsing#The restore runs once in useNewBillInitialValues]]
    useEffect(() => {
        if (!restore.values) return;

        notify({ level: "info", title: "Loaded Data from Temp Storage", duration: 1000 });
        // @lat: [[temp-bill-storage-peek-parsing#The restore runs once in useNewBillInitialValues]]
        if (restore.yielded) {
            notify({
                level: "error",
                title: "Your unsaved summary was not restored",
                message:
                    "Somebody saved a new summary for this bill while your draft was waiting. " +
                    "The saved summary is in the box. The rest of your draft came back.",
                duration: 10000,
            });
        }
    }, []);

    return useMemo(() => restore.values ?? initialBill, [restore, initialBill]);
};
