/** @format */

import { useAxiosGet, useAxiosPost } from "app/frontend/hooks/useAxios";
import { useField } from "formik";
import { useCallback, useMemo } from "react";
import { FormLabel } from "react-bootstrap";
import { MultiValue } from "react-select";
import Creatable from "react-select/creatable";
import { ISelectOption, sway } from "sway";
import { REACT_SELECT_STYLES, handleError } from "../../sway_utils";
import BillCreatorOrganization from "../bill/creator/BillCreatorOrganization";

interface IProps {
    swayFieldName: string;
    error: string | undefined;
    handleSetTouched: (fieldname: string) => void;
}

const BillCreatorOrganizations: React.FC<IProps> = ({ swayFieldName, error, handleSetTouched }) => {
    const {
        items: organizations,
        get: getOrganizations,
        isLoading: isLoadingOrganizations,
    } = useAxiosGet<sway.IOrganization[]>("/organizations", {
        skipInitialRequest: false,
        notifyOnValidationResultFailure: true,
    });

    const [formikField, , { setValue: setFieldValue }] = useField<ISelectOption[]>(swayFieldName);

    const options = useMemo(() => (organizations ?? []).map((o) => ({ label: o.name, value: o.id })), [organizations]);
    const handleSelectOrganization = useCallback(
        (newValues: MultiValue<ISelectOption>) => {
            if (newValues) {
                setFieldValue(newValues as ISelectOption[]).catch(console.error);
            }
        },
        [setFieldValue],
    );

    const { post: createOrganization } = useAxiosPost<sway.IOrganization>("/organizations", { notifyOnValidationResultFailure: true });

    const mappedSelectedOrgs = useMemo(
        () =>
            formikField.value.map((option, index) => {
                if (!option) return null;

                return (
                    <BillCreatorOrganization
                        key={`${option.value}-${index}`}
                        swayFieldName={`${swayFieldName}.${index}`}
                        organization={{ id: option.value, name: option.label } as sway.IOrganizationBase}
                        handleSetTouched={handleSetTouched}
                        error={error || ""}
                    />
                );
            }),
        [formikField.value, swayFieldName, handleSetTouched, error],
    );

    const handleCreateOption = useCallback(
        (name: string) => {
            createOrganization({ name })
                .then((result) => {
                    if (result?.id) {
                        setFieldValue(formikField.value.concat({ label: name, value: result.id })).catch(console.error);
                    }
                    getOrganizations().catch(console.error);
                })
                .catch(handleError);
        },
        [createOrganization, formikField.value, getOrganizations, setFieldValue],
    );

    return (
        <div className="col">
            <div className="row">
                <div className="col">
                    <FormLabel className="bold">
                        {formikField.name.toLowerCase().includes("oppose") ? "Opposing" : "Supporting"} Organizations
                        {" (Optional)"}
                    </FormLabel>
                    <Creatable
                        isMulti
                        isClearable
                        isSearchable
                        name={formikField.name}
                        value={formikField.value}
                        options={options}
                        onCreateOption={handleCreateOption}
                        onChange={handleSelectOrganization}
                        isDisabled={isLoadingOrganizations}
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
