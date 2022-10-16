/** @format */

import { get, isEmptyObject, logDev } from "@sway/utils";
import { useEffect, useState } from "react";
import { FormLabel } from "react-bootstrap";
import { MultiValue } from "react-select";
import Creatable from "react-select/creatable";
import { sway } from "sway";
import { useSwayFireClient } from "../../hooks/useSwayFireClient";
import { handleError, REACT_SELECT_STYLES } from "../../utils";
import BillCreatorOrganization from "../bill/creator/BillCreatorOrganization";
import { IDataOrganizationPosition, TDataOrganizationPositions } from "./types";

interface IProps {
    field: sway.IFormField;
    values: sway.IPlainObject;
    errors: sway.IPlainObject;
    touched: sway.IPlainObject;
    setFieldValue: (
        fieldname: string,
        fieldvalue: string[] | string | boolean | TDataOrganizationPositions | null,
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
    const swayFireClient = useSwayFireClient();
    const [options, setOptions] = useState<sway.TOption[]>(field.possibleValues || []);
    useEffect(() => {
        if (field.possibleValues) {
            setOptions(field.possibleValues);
        }
    }, [field.possibleValues]);

    const value = (
        isEmptyObject(values[field.name]) ? [] : values[field.name]
    ) as TDataOrganizationPositions;
    logDev("BillCreatorOrganizations.field -", { field, value, possible: field.possibleValues });

    const mappedSelectedOrgs = value.map((org, index: number) => {
        if (!org) return null;

        const fieldname = `${field.name}.${index}`;
        const positionFieldname = `${fieldname}.position`;
        const supportsFieldname = `${fieldname}.support`;
        const opposesFieldname = `${fieldname}.oppose`;

        const supportcheck = get(values, supportsFieldname);
        const opposecheck = get(values, opposesFieldname);

        const isSupporting = Boolean(supportcheck && !opposecheck);

        const handleSetFieldValue = (name: string, val: string[] | string | boolean | null) => {
            logDev("BillCreatorOrganizations.mappedSelectedOrgs.handleSetFieldValue -", name, val);
            setFieldValue(name, val);
        };

        return (
            <BillCreatorOrganization
                key={`${org}-${index}`}
                organizationName={org.value}
                fieldname={fieldname}
                isSupporting={isSupporting}
                setFieldValue={handleSetFieldValue}
                handleSetTouched={handleSetTouched}
                error={get(errors, positionFieldname)}
            />
        );
    });

    const handleCreateOption = (name: string) => {
        swayFireClient
            .organizations()
            .create({
                name,
                iconPath: "",
                positions: {},
            })
            .then((newOrg: sway.IOrganization | void) => {
                if (newOrg) {
                    setOptions(options.concat({ label: name, value: name }));
                }
            })
            .catch(handleError);
    };

    const handleChangeOrganization = (changed: MultiValue<IDataOrganizationPosition>) => {
        logDev("BillCreatorOrganizations.CHANGED", { changed });
        setFieldValue(
            field.name,
            changed.map((c) => ({
                ...c,
                position: c.position || "",
                support: c.support || false,
            })),
        );
    };

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <FormLabel>
                        {field.label} supporting and opposing
                        {field.isRequired ? " *" : " (Optional)"}
                    </FormLabel>
                    <Creatable
                        isMulti
                        isClearable
                        isSearchable
                        name={field.name}
                        value={values[field.name]}
                        options={options}
                        onCreateOption={handleCreateOption}
                        onChange={handleChangeOrganization}
                        styles={REACT_SELECT_STYLES}
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
