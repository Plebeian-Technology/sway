import { usePage } from "@inertiajs/react";
import { useLocale } from "app/frontend/hooks/useLocales";
import { isCongressLocale, titleize, toSelectOption } from "app/frontend/sway_utils";
import { sortBy } from "lodash";
import { useMemo } from "react";
import { ISelectOption, sway } from "sway";

export const useAssignValues = <T>(swayField: sway.IFormField<T>) => {
    const [locale] = useLocale();
    const legislators = usePage().props.legislators as sway.ILegislator[];

    const legislatorOptions = useMemo(
        () =>
            sortBy(
                (legislators ?? []).map((l: sway.ILegislator) => ({
                    label: `${titleize(l.lastName)}, ${titleize(l.firstName)} (${l.district.regionCode} - ${
                        l.district.number
                    })`,
                    value: l.id,
                })),
                ["label"],
            ),
        [legislators],
    ) as ISelectOption[];

    if (swayField.name === "legislator_id") {
        swayField.possibleValues = legislatorOptions;
    } else if (swayField.name === "bill.chamber") {
        if (isCongressLocale(locale)) {
            swayField.possibleValues = [toSelectOption("house", "house"), toSelectOption("senate", "senate")];
        } else {
            swayField.possibleValues = [toSelectOption("council", "council")];
        }
    } else {
        swayField.possibleValues = swayField.possibleValues || [];
    }
};
