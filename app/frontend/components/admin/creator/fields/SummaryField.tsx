import BillCreatorSummaryAudio from "app/frontend/components/admin/creator/BillCreatorSummaryAudio";
import BillCreatorSummary from "app/frontend/components/bill/BillCreatorSummary";
import { useLocale } from "app/frontend/hooks/useLocales";
import { forwardRef, Ref, useMemo } from "react";
import { Form } from "react-bootstrap";
import { sway } from "sway";

interface IProps<T> {
    swayField: sway.IFormField<T>;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}

const SummaryField = <T,>({ swayField, onBlur }: IProps<T>, summaryRef: React.Ref<string>) => {
    const [locale] = useLocale();

    const field: sway.IFormField<T> = useMemo(
        () => ({
            ...swayField,
            disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
        }),
        [locale, swayField],
    );

    return (
        <Form.Group key={swayField.name} controlId={swayField.name} className={"col"}>
            <Form.Label className="bold">
                {swayField.label}
                {swayField.isRequired ? " *" : " (Optional)"}
            </Form.Label>
            <BillCreatorSummary ref={summaryRef} field={field} onBlur={onBlur} />
            <BillCreatorSummaryAudio onBlur={onBlur} />
        </Form.Group>
    );
};

// https://stackoverflow.com/a/78692562/6410635
export default forwardRef(SummaryField) as <T>(
    props: IProps<T> & { ref?: Ref<string> },
) => ReturnType<typeof SummaryField>;
