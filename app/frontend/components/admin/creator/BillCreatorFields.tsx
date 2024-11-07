import BillCreatorField from "app/frontend/components/admin/creator/BillCreatorField";
import { ISubmitValues } from "app/frontend/components/admin/types";
import { BILL_INPUTS } from "app/frontend/components/bill/creator/inputs";
import { useLocale } from "app/frontend/hooks/useLocales";
import { isCongressLocale, titleize, toSelectOption } from "app/frontend/sway_utils";
import { useFormikContext } from "formik";
import { get, sortBy } from "lodash";
import { forwardRef, useCallback, useMemo } from "react";
import { ISelectOption, sway } from "sway";

interface IProps {
    legislators: sway.ILegislator[];
}

const BillCreatorFields = forwardRef(({ legislators }: IProps, summaryRef: React.Ref<string>) => {
    const [locale] = useLocale();

    const { values } = useFormikContext<ISubmitValues>();

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
    );

    const assignPossibleValues = useCallback(
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

    return useMemo(() => {
        const render = [] as React.ReactNode[];
        let i = 0;
        while (i < BILL_INPUTS.length) {
            const fieldGroup = BILL_INPUTS[i];

            const row = [];
            for (const swayField of fieldGroup) {
                row.push(
                    <BillCreatorField
                        ref={summaryRef}
                        swayField={swayField}
                        fieldGroup={fieldGroup}
                        assignPossibleValues={assignPossibleValues}
                    />,
                );
            }

            if (row.length) {
                render.push(
                    <div
                        key={`row-${render.length}`}
                        className={`row my-3 p-3 ${fieldGroup.first().component === "separator" ? "" : "border rounded"}`}
                    >
                        {row}
                    </div>,
                );
            }

            i++;
        }
        return render;
    }, [assignPossibleValues, summaryRef]);
});

export default BillCreatorFields;
