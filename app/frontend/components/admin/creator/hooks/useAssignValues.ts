import { usePage } from "@inertiajs/react";
import { useLocale } from "app/frontend/hooks/useLocales";
import { isCongressLocale, titleize, toSelectOption } from "app/frontend/sway_utils";
import { sortBy } from "lodash";
import { useMemo } from "react";
import { ISelectOption, sway } from "sway";

export const useAssignValues = <T>(swayField: sway.IFormField<T>): ISelectOption[] => {
    const [locale] = useLocale();
    const legislators = usePage().props.legislators as sway.ILegislator[];

    const legislatorOptions = useMemo(
        () =>
            sortBy(
                (legislators ?? []).map((l: sway.ILegislator) => ({
                    label: `${titleize(l.last_name)}, ${titleize(l.first_name)} (${l.district.region_code} - ${
                        l.district.number
                    })`,
                    value: l.id,
                })),
                ["label"],
            ),
        [legislators],
    ) as ISelectOption[];

    return useMemo(() => {
        if (swayField.name === "legislator_id") {
            return legislatorOptions;
        } else if (swayField.name === "bill.chamber") {
            if (isCongressLocale(locale)) {
                return [toSelectOption("house", "house"), toSelectOption("senate", "senate")];
            } else {
                return [toSelectOption("council", "council")];
            }
        } else {
            return (swayField.possibleValues as ISelectOption[]) || [];
        }
    }, [swayField.name, swayField.possibleValues, legislatorOptions, locale]);
};
