/** @format */

import { get, logDev } from "@sway/utils";
import { sway } from "sway";
import BillCreatorOrganization from "../bill/creator/BillCreatorOrganization";
import SwayAutoSelect from "../forms/SwayAutoSelect";
import { IDataOrganizationPositions } from "./types";

interface IProps {
    field: sway.IFormField;
    values: sway.IPlainObject;
    errors: sway.IPlainObject;
    touched: sway.IPlainObject;
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
    handleSetTouched: (fieldname: string) => void;
}

const BillCreatorOrganizations: React.FC<IProps> = ({
    field,
    values,
    errors,
    setFieldValue,
    handleSetTouched,
}) => {
    logDev("BillCreatorOrganizations.field -", field, values[field.name]);
    const selectedOrganizationNames = values[field.name] || ({} as IDataOrganizationPositions);

    const mappedSelectedOrgs = Object.keys(selectedOrganizationNames).map(
        (org: string, index: number) => {
            const fieldname = `${field.name}.${org}`;
            const positionFieldname = `${fieldname}.position`;
            const supportsFieldname = `${fieldname}.support`;
            const opposesFieldname = `${fieldname}.oppose`;

            const supportcheck = get(values, supportsFieldname);
            const opposecheck = get(values, opposesFieldname);

            const isSupporting = Boolean(supportcheck && !opposecheck);

            const handleSetFieldValue_ = (
                name: string,
                value: string[] | string | boolean | null,
            ) => {
                logDev(
                    "BillCreatorOrganizations.mappedSelectedOrgs.handleSetFieldValue_ -",
                    name,
                    value,
                );
                setFieldValue(name, value);
            };

            return (
                <BillCreatorOrganization
                    key={`${org}-${index}`}
                    organizationName={org}
                    fieldname={fieldname}
                    isSupporting={isSupporting}
                    setFieldValue={handleSetFieldValue_}
                    handleSetTouched={handleSetTouched}
                    error={get(errors, positionFieldname)}
                />
            );
        },
    );

    const handleSetFieldValue = (
        fieldname: string,
        fieldvalue: string[] | string | boolean | null,
    ) => {
        // @ts-ignore
        setFieldValue(`${fieldname}.${fieldvalue}`, {});
    };

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <SwayAutoSelect
                        key={field.name}
                        field={field}
                        value={values[field.name]}
                        error={errors[field.name]}
                        setFieldValue={handleSetFieldValue}
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
