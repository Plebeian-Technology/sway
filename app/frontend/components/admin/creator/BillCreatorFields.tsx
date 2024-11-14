import BillCreatorField from "app/frontend/components/admin/creator/BillCreatorField";
import { BILL_INPUTS } from "app/frontend/components/bill/creator/inputs";
import { forwardRef } from "react";

const BillCreatorFields = forwardRef(({}, summaryRef: React.Ref<string>) => {
    const render = [] as React.ReactNode[];

    const pushRow = (row: React.ReactNode[], isSeparator: boolean) => {
        render.push(
            <div key={`row-${render.length}`} className={`row my-3 p-3 ${isSeparator ? "" : "border rounded"}`}>
                {row}
            </div>,
        );
    };

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
            pushRow(row, fieldGroup.first().component === "separator");
        }

        i++;
    }
    return render;
});

export default BillCreatorFields;
