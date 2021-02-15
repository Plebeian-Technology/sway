/** @format */

import { createStyles, makeStyles, Theme } from "@material-ui/core";
import { sway } from "sway";
import React from "react";

import SwayAutoSelect from "../forms/SwayAutoSelect";
import SwayFormCheckbox from "../forms/SwayFormCheckbox";
import SwayTextArea from "../forms/SwayTextArea";
import { get } from "@sway/utils"

interface IProps {
    field: sway.IFormField;
    values: sway.IPlainObject;
    errors: sway.IPlainObject;
    touched: sway.IPlainObject;
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
    handleSetTouched: (fieldname: string) => void;
}

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        row: {
            display: "flex",
            flexDirection: "row",
            width: "100%",
            justifyContent: "center",
            flexWrap: "wrap",
        },
        org: {
            width: "45%",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            margin: theme.spacing(1),
        },
        position: {
            width: "100%",
        },
        checkboxgroup: {
            display: "flex",
            flexDirection: "row",
            justifyContent: "flex-start",
            width: "100%",
        }
    })
);

const BillCreatorOrganizations: React.FC<IProps> = ({
    field,
    values,
    errors,
    setFieldValue,
    handleSetTouched,
}) => {
    const classes = useStyles();
    const selectedOrganizations = values[field.name] || [];

    const mappedSelectedOrgs = selectedOrganizations.map((org: string, index: number) => {
        const fieldname = `positions.${org}`;
        const positionFieldname = `${fieldname}.position`
        const supportsFieldname = `${fieldname}.support`
        const opposesFieldname = `${fieldname}.oppose`

        const supportcheck = get(values, supportsFieldname);
        const opposecheck = get(values, opposesFieldname);

        return (
            <div key={`${org}-${index}`} className={classes.org}>
                <div className={classes.checkboxgroup}>
                <SwayFormCheckbox
                    field={{
                        name: supportsFieldname,
                        component: "checkbox",
                        type: "boolean",
                        label: "Support?",
                        isRequired: false,
                    }}
                    value={supportcheck && !opposecheck}
                    error={get(errors, supportsFieldname)}
                    setFieldValue={setFieldValue}
                    handleSetTouched={handleSetTouched}
                />
                <SwayFormCheckbox
                    field={{
                        name: opposesFieldname,
                        component: "checkbox",
                        type: "boolean",
                        label: "Oppose?",
                        isRequired: false,
                    }}
                    value={opposecheck && !supportcheck}
                    error={get(errors, opposesFieldname)}
                    setFieldValue={setFieldValue}
                    handleSetTouched={handleSetTouched}
                />
                </div>
                <div className={classes.position}>
                <SwayTextArea
                    style={{ width: "100%" }}
                    field={{
                        name: positionFieldname,
                        component: "textarea",
                        type: "text",
                        label: `${org} Position Summary`,
                        isRequired: true,
                    }}
                    value={values[positionFieldname]}
                    error={errors[positionFieldname]}
                    setFieldValue={setFieldValue}
                    handleSetTouched={handleSetTouched}
                />
                </div>
            </div>
        );
    });

    return (
        <>
            <SwayAutoSelect
                key={field.name}
                field={field}
                value={values[field.name]}
                error={errors[field.name]}
                setFieldValue={setFieldValue}
                handleSetTouched={handleSetTouched}
                multiple={true}
            />
            <div className={classes.row}>{mappedSelectedOrgs}</div>
        </>
    );
};

export default BillCreatorOrganizations;
