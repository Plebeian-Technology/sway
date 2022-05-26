/** @format */

import { get, isNumeric, logDev } from "@sway/utils";
import { FormLabel } from "react-bootstrap";
import Select from "react-select";
import { sway } from "sway";
import BillCreatorOrganization from "../bill/creator/BillCreatorOrganization";

interface IProps {
    field: sway.IFormField;
    values: sway.IPlainObject;
    errors: sway.IPlainObject;
    touched: sway.IPlainObject;
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
    handleSetTouched: (fieldname: string) => void;
}

interface IOrganizationOption extends sway.TOption {
    position: string;
    support: boolean;
}

const BillCreatorOrganizations: React.FC<IProps> = ({
    field,
    values,
    errors,
    setFieldValue,
    handleSetTouched,
}) => {
    const value: IOrganizationOption[] = values[field.name] || {};
    logDev("BillCreatorOrganizations.field -", { field, value, possible: field.possibleValues });

    const mappedSelectedOrgs = Object.keys(value).map((org: string, index: number) => {
        if (isNumeric(org)) {
            // eslint-disable-next-line
            org = value[org].label;
        }

        const fieldname = `${field.name}.${org}`;
        const positionFieldname = `${fieldname}.position`;
        const supportsFieldname = `${fieldname}.support`;
        const opposesFieldname = `${fieldname}.oppose`;

        const supportcheck = get(values, supportsFieldname);
        const opposecheck = get(values, opposesFieldname);

        const isSupporting = Boolean(supportcheck && !opposecheck);

        const handleSetFieldValue_ = (name: string, val: string[] | string | boolean | null) => {
            logDev("BillCreatorOrganizations.mappedSelectedOrgs.handleSetFieldValue_ -", name, val);
            setFieldValue(name, val);
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
    });

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
