/** @format */

import { Checkbox } from "@material-ui/core";
import { Field } from "formik";
import React from "react";
import { sway } from "sway";

import SwayBase from "./SwayBase";

interface IProps {
    field: sway.IFormField;
    value: boolean;
    error: string;
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
    handleSetTouched: (fieldname: string) => void
}

const SwayCheckbox: React.FC<IProps> = ({
    field,
    value,
    setFieldValue,
    handleSetTouched,
}) => {
    return (
        <SwayBase style={{ textAlign: "center" }}>
            {`${field.label} - ${value}`}
            <Field
                type={"checkbox"}
                name={field.name}
                component={Checkbox}
                onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
                    setFieldValue(field.name, event?.target.checked);
                    handleSetTouched(field.name);
                }}
            />
        </SwayBase>
    );
};

export default SwayCheckbox;
