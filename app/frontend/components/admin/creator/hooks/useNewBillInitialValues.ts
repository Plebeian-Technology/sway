/* eslint-disable react-hooks/exhaustive-deps */

/** @format */
import { ESwayLevel } from "app/frontend/sway_constants";
import { isCongressLocale, SWAY_STORAGE, toSelectOption } from "app/frontend/sway_utils";
import { useMemo } from "react";
import { sway } from "sway";

import { usePage } from "@inertiajs/react";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useLocale } from "app/frontend/hooks/useLocales";

export const useNewBillInitialValues = (): IApiBillCreator => {
    const [locale] = useLocale();
    const bill = usePage().props.bill as sway.IBill;
    const legislators = usePage().props.legislators as sway.ILegislator[];
    const organizations = usePage().props.organizations as sway.IOrganization[];

    const initialBill = useMemo(
        () => ({
            id: bill.id,
            external_id: bill?.externalId?.trim() || "",
            external_version: bill?.externalVersion?.trim() || "",
            title: bill?.title?.trim() || "",
            link: bill?.link?.trim() || "",
            legislator_id: bill?.legislatorId || null,
            chamber:
                bill?.chamber ||
                (isCongressLocale(locale) ? toSelectOption("house", "house") : toSelectOption("Council", "council")),
            level: bill?.level?.trim() || ESwayLevel.Local,
            summary: bill?.summary?.trim() ?? "",
            summary_preview: bill?.summary?.trim() ?? "",
            category: bill?.category ?? "",
            status: bill?.status?.trim() ?? "",
            active: typeof bill?.active === "boolean" ? bill.active : true,

            introduced_date_time_utc: bill?.introducedDateTimeUtc ? new Date(bill?.introducedDateTimeUtc) : null,
            withdrawn_date_time_utc: bill?.withdrawnDateTimeUtc ? new Date(bill?.withdrawnDateTimeUtc) : null,
            house_vote_date_time_utc: bill?.houseVoteDateTimeUtc ? new Date(bill?.houseVoteDateTimeUtc) : null,
            senate_vote_date_time_utc: bill?.senateVoteDateTimeUtc ? new Date(bill?.senateVoteDateTimeUtc) : null,

            sway_locale_id: locale.id,

            audio_bucket_path: bill?.audioBucketPath?.trim() || "",
            audio_by_line: bill?.audioByLine?.trim() || "",

            house_roll_call_vote_number: bill?.vote?.houseRollCallVoteNumber ?? "",
            senate_roll_call_vote_number: bill?.vote?.senateRollCallVoteNumber ?? "",
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
            // sponsor: legislators.find((l) => l.id === bill.legislatorId),
            // legislatorVotes,
            // organizations,
            // } as ISubmitValues;
        }
    }, [initialBill, legislators, organizations]);
};
