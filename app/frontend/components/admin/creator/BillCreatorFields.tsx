import BillCreatorField from "app/frontend/components/admin/creator/BillCreatorField";
import { BILL_INPUTS } from "app/frontend/components/bill/creator/inputs";
import { forwardRef, useMemo } from "react";

const BillCreatorFields = forwardRef(({}, summaryRef: React.Ref<string>) => {
    return useMemo(() => {
        const render = [] as React.ReactNode[];
        let i = 0;
        while (i < BILL_INPUTS.length) {
            const fieldGroup = BILL_INPUTS[i];

            const row = [];
            for (const swayField of fieldGroup) {
                row.push(
                    <BillCreatorField
                        key={`bill-creator-field-${swayField.name}`}
                        ref={summaryRef}
                        swayField={swayField}
                        fieldGroup={fieldGroup}
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
    }, [summaryRef]);
});

export default BillCreatorFields;
