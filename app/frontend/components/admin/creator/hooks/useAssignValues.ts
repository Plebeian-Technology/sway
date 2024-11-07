import { usePage } from "@inertiajs/react";
import { ISubmitValues } from "app/frontend/components/admin/types";
import { useLocale } from "app/frontend/hooks/useLocales";
import { isCongressLocale, titleize, toSelectOption } from "app/frontend/sway_utils";
import { useFormikContext } from "formik";
import { get, sortBy } from "lodash";
import { useCallback, useMemo } from "react";
import { ISelectOption, sway } from "sway";

export const useAssignValues = () => {
    const { values } = useFormikContext<ISubmitValues>();

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

    return useCallback(
        (swayField: sway.IFormField): ISelectOption[] => {
            if (swayField.name === "legislator") {
                return legislatorOptions;
            } else if (swayField.name === "chamber") {
                if (isCongressLocale(locale)) {
                    return [toSelectOption("house", "house"), toSelectOption("senate", "senate")];
                } else {
                    return [toSelectOption("council", "council")];
                }
            } else if (["supporters", "opposers", "abstainers"].includes(swayField.name)) {
                const selectedSupporter = get(values, "supporters") || [];
                const selectedOpposer = get(values, "opposers") || [];
                const selectedAbstainer = get(values, "abstainers") || [];
                const selected = selectedSupporter.concat(selectedOpposer).concat(selectedAbstainer);

                return legislatorOptions.filter((o) => !selected.find((s) => s.value === o.value));
            } else {
                return swayField.possibleValues || [];
            }
        },
        [legislatorOptions, locale, values],
    );
};
