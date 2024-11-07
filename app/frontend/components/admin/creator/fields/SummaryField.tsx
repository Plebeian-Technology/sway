import BillCreatorSummaryAudio from "app/frontend/components/admin/BillCreatorSummaryAudio";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import BillCreatorSummary from "app/frontend/components/bill/BillCreatorSummary";
import { useLocale } from "app/frontend/hooks/useLocales";
import { forwardRef } from "react";
import { Form } from "react-bootstrap";

const SummaryField = forwardRef(({ swayField }: IFieldProps, summaryRef: React.Ref<string>) => {
    const [locale] = useLocale();

    return (
        <Form.Group key={swayField.name} controlId={swayField.name} className={"col"}>
            <Form.Label className="bold">
                {swayField.label}
                {swayField.isRequired ? " *" : " (Optional)"}
            </Form.Label>
            <BillCreatorSummary
                ref={summaryRef}
                field={{
                    ...swayField,
                    disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
                }}
            />
            <BillCreatorSummaryAudio />
        </Form.Group>
    );
});

export default SummaryField;
