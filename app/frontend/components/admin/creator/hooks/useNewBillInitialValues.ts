/* eslint-disable react-hooks/exhaustive-deps */

/** @format */
import { isCongressLocale, SWAY_STORAGE, toSelectOption } from "app/frontend/sway_utils";
import { useMemo } from "react";
import { sway } from "sway";

import { usePage } from "@inertiajs/react";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useLocale } from "app/frontend/hooks/useLocales";
import { parseISO } from "date-fns";

export const useNewBillInitialValues = (): IApiBillCreator => {
    const [locale] = useLocale();
    const bill = usePage().props.bill as sway.IBill;
    const legislators = usePage().props.legislators as sway.ILegislator[];
    const organizations = usePage().props.organizations as sway.IOrganization[];

    const initialBill = useMemo(
        () => ({
            id: bill.id,
            external_id: bill?.external_id?.trim() || "",
            external_version: bill?.external_version?.trim() || "",
            title: bill?.title?.trim() || "",
            link: bill?.link?.trim() || "",
            legislator_id: bill?.legislator_id || null,
            chamber:
                bill?.chamber ||
                (isCongressLocale(locale) ? toSelectOption("house", "house") : toSelectOption("Council", "council")),
            summary: bill?.summary?.trim() ?? "",
            summary_preview: bill?.summary?.trim() ?? "",
            category: bill?.category ?? "",
            status: bill?.status?.trim() ?? ("committee" as sway.TBillStatus),
            active: typeof bill?.active === "boolean" ? bill.active : true,

            introduced_date_time_utc: bill?.introduced_date_time_utc ? parseISO(bill?.introduced_date_time_utc) : null,
            withdrawn_date_time_utc: bill?.withdrawn_date_time_utc ? parseISO(bill?.withdrawn_date_time_utc) : null,
            house_vote_date_time_utc: bill?.house_vote_date_time_utc ? parseISO(bill?.house_vote_date_time_utc) : null,
            senate_vote_date_time_utc: bill?.senate_vote_date_time_utc
                ? parseISO(bill?.senate_vote_date_time_utc)
                : null,

            sway_locale_id: locale.id,

            audio_bucket_path: bill?.audio_bucket_path?.trim() || "",
            audio_by_line: bill?.audio_by_line?.trim() || "",

            house_roll_call_vote_number: bill?.vote?.house_roll_call_vote_number ?? "",
            senate_roll_call_vote_number: bill?.vote?.senate_roll_call_vote_number ?? "",
        }),
        [bill, locale],
    );

    return useMemo(() => {
        const stored = new TempBillStorage(SWAY_STORAGE.Local.BillOfTheWeek.Bill).get();
        if (stored) {
            return stored;
        } else {
            return initialBill;
            // bill: initialBill,
            // sponsor: legislators.find((l) => l.id === bill.legislator_id),
            // legislator_votes,
            // organizations,
            // } as ISubmitValues;
        }
    }, [initialBill, legislators, organizations]);
};
