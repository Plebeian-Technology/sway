/** @format */

import { Checkbox, FormLabel } from "@mui/material";
import { Field } from "formik";
import { sway } from "sway";

interface IProps {
    field: sway.IFormField;
    value: boolean;
    error: string;
    setFieldValue: (
        fieldname: string,
        fieldvalue: string[] | string | boolean | null,
    ) => void;
    handleSetTouched: (fieldname: string) => void;
}

const SwayFormCheckbox: React.FC<IProps> = ({
    field,
    value,
    setFieldValue,
    handleSetTouched,
}) => {
    return (
        <>
            <FormLabel className="mr-2">
                {`${field.label} - ${value}`}
            </FormLabel>
            &nbsp;
            <Field
                type={"checkbox"}
                className="p-2"
                size={"1.5em"}
                name={field.name}
                component={Checkbox}
                onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
                    setFieldValue(field.name, event?.target.checked);
                    handleSetTouched(field.name);
                }}
            />
        </>
    );
};

export default SwayFormCheckbox;
