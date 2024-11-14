/* eslint-disable react-hooks/exhaustive-deps */

/** @format */
import { ESwayLevel, Support } from "app/frontend/sway_constants";
import { isCongressLocale, toSelectOption } from "app/frontend/sway_utils";
import { useMemo } from "react";
import { ISelectOption, sway } from "sway";

import { usePage } from "@inertiajs/react";
import { ISubmitValues } from "app/frontend/components/admin/types";
import { useLocale } from "app/frontend/hooks/useLocales";

import "react-datepicker/dist/react-datepicker.css";

export const useNewBillInitialValues = () => {
    const [locale] = useLocale();
    const bill = usePage().props.bill as sway.IBill;
    const legislators = usePage().props.legislators as sway.ILegislator[];
    const legislatorVotes = usePage().props.legislatorVotes as sway.ILegislatorVote[];
    const organizationPositions = usePage().props.positions as sway.IOrganizationPosition[];

    const initialBill = useMemo(
        () => ({
            id: bill.id,
            externalId: bill?.externalId?.trim() || "",
            externalVersion: bill?.externalVersion?.trim() || "",
            title: bill?.title?.trim() || "",
            link: bill?.link?.trim() || "",
            legislatorId: bill?.legislatorId || null,
            chamber:
                bill?.chamber ||
                (isCongressLocale(locale) ? toSelectOption("house", "house") : toSelectOption("council", "council")),
            level: bill?.level?.trim() || ESwayLevel.Local,
            summary: bill?.summary?.trim() ?? "",
            category: bill?.category ? toSelectOption(bill.category.trim(), bill.category.trim()) : undefined,
            status: bill?.status?.trim() ?? "",
            active: typeof bill?.active === "boolean" ? bill.active : true,

            introducedDateTimeUtc: bill?.introducedDateTimeUtc ?? "",
            houseVoteDateTimeUtc: bill?.houseVoteDateTimeUtc ?? "",
            senateVoteDateTimeUtc: bill?.senateVoteDateTimeUtc ?? "",

            houseRollCallVoteNumber: bill?.vote?.houseRollCallVoteNumber ?? "",
            senateRollCallVoteNumber: bill?.vote?.senateRollCallVoteNumber ?? "",

            swayLocaleId: locale.id,

            audioBucketPath: bill?.audioBucketPath?.trim() || "",
            audioByLine: bill?.audioByLine?.trim() || "",
        }),
        [bill, locale],
    );

    const { supporters, opposers, abstainers } = useMemo(() => {
        const s = [] as ISelectOption[];
        const o = [] as ISelectOption[];
        const a = [] as ISelectOption[];
        for (const lv of legislatorVotes) {
            const legislator = legislators.find((l) => l.id === lv.legislatorId);
            if (!legislator) continue;

            switch (lv.support) {
                case Support.For:
                    s.push({ label: legislator.fullName, value: lv.legislatorId });
                    break;
                case Support.Against:
                    o.push({ label: legislator.fullName, value: lv.legislatorId });
                    break;
                case Support.Abstain:
                    a.push({ label: legislator.fullName, value: lv.legislatorId });
                    break;
            }
        }
        return { supporters: s, opposers: o, abstainers: a };
    }, []);

    return useMemo(
        () =>
            ({
                ...initialBill,
                legislator: legislatorToSelectOption(legislators.find((l) => l.id === initialBill.legislatorId)),

                supporters,
                opposers,
                abstainers,

                organizationsSupport: (organizationPositions || [])
                    .filter((p) => p.support === Support.For)
                    .map((p) => ({
                        label: p.organization.name,
                        value: p.organization.id,
                        summary: p.summary,
                        iconPath: p.organization.iconPath,
                    })),
                organizationsOppose: (organizationPositions || [])
                    .filter((p) => p.support === Support.Against)
                    .map((p) => ({
                        label: p.organization.name,
                        value: p.organization.id,
                        summary: p.summary,
                        iconPath: p.organization.iconPath,
                    })),
            }) as ISubmitValues,
        [initialBill, legislators, organizationPositions, supporters, opposers, abstainers],
    );
};

const legislatorToSelectOption = (legislator?: sway.ILegislator | null) => {
    if (!legislator) return;

    return {
        label: legislator.fullName,
        value: legislator.id,
    };
};
