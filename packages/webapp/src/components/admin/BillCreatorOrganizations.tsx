/** @format */

import { FormControlLabel, Switch } from "@mui/material";
import { get } from "@sway/utils";
import { sway } from "sway";
import SwayAutoSelect from "../forms/SwayAutoSelect";
import SwayTextArea from "../forms/SwayTextArea";

interface IProps {
    field: sway.IFormField;
    values: sway.IPlainObject;
    errors: sway.IPlainObject;
    touched: sway.IPlainObject;
    setFieldValue: (
        fieldname: string,
        fieldvalue: string[] | string | boolean | null,
    ) => void;
    handleSetTouched: (fieldname: string) => void;
}

const BillCreatorOrganizations: React.FC<IProps> = ({
    field,
    values,
    errors,
    setFieldValue,
    handleSetTouched,
}) => {
    const selectedOrganizations = values[field.name] || [];

    const mappedSelectedOrgs = selectedOrganizations.map(
        (org: string, index: number) => {
            const fieldname = `positions.${org}`;
            const positionFieldname = `${fieldname}.position`;
            const supportsFieldname = `${fieldname}.support`;
            const opposesFieldname = `${fieldname}.oppose`;

            const supportcheck = get(values, supportsFieldname);
            const opposecheck = get(values, opposesFieldname);

            const isSupporting = Boolean(supportcheck && !opposecheck);

            return (
                <div key={`${org}-${index}`} className="col">
                    <div className="row">
                        <div className="col">
                            <FormControlLabel
                                label={isSupporting ? "Supports" : "Opposes"}
                                control={
                                    <Switch
                                        name={supportsFieldname}
                                        checked={isSupporting}
                                        onChange={(
                                            event: React.ChangeEvent<HTMLInputElement>,
                                        ) => {
                                            setFieldValue(
                                                supportsFieldname,
                                                event?.target.checked,
                                            );
                                            handleSetTouched(supportsFieldname);
                                        }}
                                    />
                                }
                            />
                        </div>
                    </div>
                    <div className="row">
                        <div className="col">
                            <SwayTextArea
                                field={{
                                    name: positionFieldname,
                                    component: "textarea",
                                    type: "text",
                                    label: `${org} Position Summary`,
                                    isRequired: true,
                                }}
                                rows={5}
                                value={values[positionFieldname]}
                                error={errors[positionFieldname]}
                                setFieldValue={setFieldValue}
                                handleSetTouched={handleSetTouched}
                                helperText={`Why does ${org} ${
                                    isSupporting ? "support" : "oppose"
                                } this bill?.`}
                            />
                        </div>
                    </div>
                </div>
            );
        },
    );

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <SwayAutoSelect
                        key={field.name}
                        field={field}
                        value={values[field.name]}
                        error={errors[field.name]}
                        setFieldValue={setFieldValue}
                        handleSetTouched={handleSetTouched}
                        multiple={true}
                        helperText={
                            "Select 0 or more organizations that have opinions about this legislation."
                        }
                    />
                </div>
            </div>
            <div className="row">
                <div className="col">{mappedSelectedOrgs}</div>
            </div>
        </div>
    );
};

export default BillCreatorOrganizations;
