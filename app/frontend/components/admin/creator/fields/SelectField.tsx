import { useAssignValues } from "app/frontend/components/admin/creator/hooks/useAssignValues";
import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";
import { IApiBillCreator, IFieldProps } from "app/frontend/components/admin/creator/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { useLocale } from "app/frontend/hooks/useLocales";
import { CONGRESS_LOCALE_NAME } from "app/frontend/sway_constants";
import { REACT_SELECT_STYLES } from "app/frontend/sway_utils";
import { useCallback } from "react";
import { Form } from "react-bootstrap";
import Select, { Options } from "react-select";
import { ISelectOption, KeyOf, sway } from "sway";

const SelectField = <T,>({ swayField, fieldGroupLength }: IFieldProps<T>) => {
    const { data, setData } = useFormContext<T>();
    const errorMessage = useErrorMessage(swayField);
    const [locale] = useLocale();
    useAssignValues<T>(swayField);

    const isRenderPositionsSelects = useCallback(
        (field: sway.IFormField<T>) => {
            if (["supporters", "opposers", "abstainers"].includes(field.name)) {
                return locale.name !== CONGRESS_LOCALE_NAME;
            } else {
                return true;
            }
        },
        [locale.name],
    );

    const getValue = (v: any) => {
        if (Array.isArray(v)) {
            return val.map((_v: any) => getValue(_v));
        } else if (["string", "number"].includes(typeof v)) {
            return (swayField.possibleValues || []).find((item) => item.value === v);
        } else {
            return v;
        }
    };

    const { name: n } = swayField;
    const name = n as KeyOf<IApiBillCreator>;
    const val = (data as Record<string, any>)[swayField.name];
    const value = getValue(val);

    return (
        <Form.Group
            key={name}
            controlId={name}
            className={`col-xs-12 col-sm-${12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4}`}
        >
            {swayField.label && (
                <Form.Label className="bold">
                    {swayField.label}
                    {swayField.isRequired ? " *" : " (Optional)"}
                </Form.Label>
            )}
            <Select
                name={name}
                styles={REACT_SELECT_STYLES}
                options={swayField.possibleValues as Options<ISelectOption>}
                isMulti={Boolean(swayField.multi)}
                isDisabled={!isRenderPositionsSelects(swayField) || swayField.disabled || swayField.disableOn?.(locale)}
                value={value}
                onChange={(changed) => {
                    setData(name, changed);
                }}
                closeMenuOnSelect={!["supporters", "opposers", "abstainers"].includes(name)}
            />
            <div className="text-danger">{errorMessage}</div>
        </Form.Group>
    );
};

export default SelectField;
