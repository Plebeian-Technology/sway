import { useCallback, useMemo } from "react";
import { sway } from "sway";
import { Input } from "app/frontend/components/ui/input";
import { useCreatorField } from "app/frontend/components/admin/creator/hooks/useCreatorField";
import { FieldShell } from "app/frontend/components/admin/creator/fields/FieldShell";

interface IProps<T> {
    swayField: sway.IFormField<T>;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}

const TextField = <T,>({ swayField, onBlur }: IProps<T>) => {
    const { data, setValue, error, disabled, value: fieldValue } = useCreatorField(swayField);

    const generatedValue = useMemo(() => {
        if (swayField.component === "generatedText" && swayField.generateFields) {
            return swayField.generateFields
                .map((fieldname: string) => (data as unknown as Record<string, string | number | undefined>)[fieldname])
                .join(swayField.joiner || " ");
        }
        return "";
    }, [data, swayField]);

    const value = swayField.component === "text" ? (fieldValue ?? "") : generatedValue;

    const onChange = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            setValue(e.target.value);
        },
        [setValue],
    );

    return (
        <FieldShell
            name={swayField.name as string}
            label={swayField.label}
            required={swayField.isRequired}
            helperText={swayField.helperText}
            error={error}
        >
            <Input
                id={swayField.name as string}
                name={swayField.name as string}
                type={swayField.type === "number" ? "number" : swayField.type}
                autoComplete={swayField.autoComplete}
                disabled={disabled}
                value={value as string}
                onChange={onChange}
                onBlur={onBlur}
                aria-invalid={error ? true : undefined}
                aria-describedby={error ? `${swayField.name as string}-error` : undefined}
            />
        </FieldShell>
    );
};

export default TextField;
