/** @format */

import { get, logDev } from "@sway/utils";
import { FormLabel } from "react-bootstrap";
import Select from "react-select";
import { sway } from "sway";
import BillCreatorOrganization from "../bill/creator/BillCreatorOrganization";
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

    logDev("VALUES", values, field.possibleValues);
    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <FormLabel>{field.label}</FormLabel>
                    <Select
                        isMulti
                        isClearable
                        isSearchable
                        name={field.name}
                        value={values[field.name]}
                        options={field.possibleValues}
                        onChange={(changed) => {
                            setFieldValue(
                                field.name,
                                changed.filter((c) => !!c.value),
                            );
                        }}
                        styles={{
                            control: (provided) => ({
                                ...provided,
                                cursor: "pointer",
                            }),
                            option: (provided) => ({
                                ...provided,
                                cursor: "pointer",
                            }),
                        }}
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
