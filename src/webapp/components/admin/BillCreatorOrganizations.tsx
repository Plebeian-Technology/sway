/** @format */

import { get } from "src/utils";
import { sway } from "sway";
import BillCreatorOrganization from "../bill/creator/BillCreatorOrganization";
import SwayAutoSelect from "../forms/SwayAutoSelect";

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
                <BillCreatorOrganization
                    key={`${org}-${index}`}
                    organizationName={org}
                    isSupporting={isSupporting}
                    setFieldValue={setFieldValue}
                    handleSetTouched={handleSetTouched}
                    error={get(errors, positionFieldname)}
                />
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
