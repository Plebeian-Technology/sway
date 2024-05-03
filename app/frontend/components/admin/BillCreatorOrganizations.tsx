/** @format */

import { useCallback, useEffect, useMemo, useState } from "react";
import { FormLabel } from "react-bootstrap";
import { MultiValue } from "react-select";
import Creatable from "react-select/creatable";
import { sway } from "sway";
import { REACT_SELECT_STYLES } from "../../sway_utils";
import BillCreatorOrganization from "../bill/creator/BillCreatorOrganization";
import { IDataOrganizationPosition, TDataOrganizationPositions } from "./types";

interface IProps {
    field: sway.IFormField;
    organizations: IDataOrganizationPosition[];
    error: string | undefined;
    touched: boolean;
    setFieldValue: (
        fieldname: string,
        fieldvalue: string[] | string | boolean | TDataOrganizationPositions | null,
    ) => void;
    handleSetTouched: (fieldname: string) => void;
    billFirestoreId: string;
}

const BillCreatorOrganizations: React.FC<IProps> = ({
    field,
    organizations,
    error,
    setFieldValue,
    handleSetTouched,
}) => {

    const [options, setOptions] = useState<sway.TOption[]>(field.possibleValues || []);
    useEffect(() => {
        if (field.possibleValues) {
            setOptions(field.possibleValues);
        }
    }, [field.possibleValues]);

    const mappedSelectedOrgs = useMemo(
        () =>
            organizations.map((org, index: number) => {
                if (!org) return null;
                return (
                    <BillCreatorOrganization
                        key={`${org}-${index}`}
                        organization={org}
                        index={index}
                        setFieldValue={setFieldValue}
                        handleSetTouched={handleSetTouched}
                        error={error || ""}
                    />
                );
            }),
        [error, handleSetTouched, setFieldValue, organizations],
    );

    const handleCreateOption = useCallback(
        (name: string) => {
            // return swayFireClient
            //     .organizations()
            //     .create({
            //         name,
            //         iconPath: "",
            //         positions: {},
            //     })
            //     .then((newOrg: sway.IOrganization | void) => {
            //         if (newOrg) {
            //             setOptions((current) => current.concat({ label: name, value: name }));
            //             setFieldValue(field.name, [
            //                 ...organizations,
            //                 {
            //                     label: name,
            //                     value: name,
            //                     support: false,
            //                     position: "",
            //                 },
            //             ] as TDataOrganizationPositions);
            //         } else {
            //             notify({
            //                 level: "warning",
            //                 title: "Failed to create organization",
            //             });
            //         }
            //     })
            //     .catch(handleError);
        },
        [field.name, organizations, setFieldValue],
    );

    const handleChangeOrganization = useCallback(
        (changed: MultiValue<IDataOrganizationPosition>) => {
            setFieldValue(
                field.name,
                changed.map((c) => ({
                    ...c,
                    position: c.position || "",
                    support: c.support || false,
                })),
            );
        },
        [field.name, setFieldValue],
    );

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <FormLabel className="bold">
                        {field.label} supporting and opposing
                        {field.isRequired ? " *" : " (Optional)"}
                    </FormLabel>
                    <Creatable
                        isMulti
                        isClearable
                        isSearchable
                        name={field.name}
                        value={organizations as sway.TOption[]}
                        options={options}
                        onCreateOption={handleCreateOption}
                        // @ts-ignore
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
