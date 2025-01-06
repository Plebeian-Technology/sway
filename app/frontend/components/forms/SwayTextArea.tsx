/** @format */

import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { withEmojis } from "app/frontend/sway_utils";
import { useCallback } from "react";
import ReactTextareaAutosize from "react-textarea-autosize";
import { sway } from "sway";

interface IProps<T> {
    field: sway.IFormField<T>;
    value: string;
    error: string | string[] | undefined;
    style?: React.CSSProperties;
    helperText?: string;
    rows?: number;
    onChange?: (e: React.ChangeEvent<HTMLTextAreaElement>) => void;
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}

const SwayTextArea = <T,>({ field, error, helperText, rows, onChange, onBlur, value }: IProps<T>) => {
    const { setData } = useFormContext<T>();

    const handleChange = useCallback(
        async (event: React.ChangeEvent<HTMLTextAreaElement>) => {
            if (onChange) {
                onChange(event);
            } else {
                setData(field.name, withEmojis(event?.target?.value));
            }
        },
        [onChange, setData, field.name],
    );

    const wordCount = value?.match(/\s/g)?.length || (value.length ? 1 : 0);

    return (
        <>
            <ReactTextareaAutosize
                onChange={handleChange}
                required={field.isRequired}
                // label={field.label}
                // variant={"outlined"}
                // component={ReactTextareaAutosize}
                // multiline={"true"}
                minRows={rows || 5}
                // type={field.type}
                name={field.name}
                className="w-100 p-2"
                value={value}
                onBlur={onBlur}
            />
            <div className="text-muted">
                {helperText ? `${helperText} | Word Count - ${wordCount}` : `Word Count - ${wordCount}`}
            </div>
            <div className="text-danger">{error}</div>
        </>
    );
};

export default SwayTextArea;
