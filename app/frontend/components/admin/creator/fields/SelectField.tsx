import { useAssignValues } from "app/frontend/components/admin/creator/hooks/useAssignValues";
import { IFieldProps } from "app/frontend/components/admin/creator/types";
import { useLocale } from "app/frontend/hooks/useLocales";
import { CONGRESS_LOCALE_NAME } from "app/frontend/sway_constants";
import { REACT_SELECT_STYLES } from "app/frontend/sway_utils";
import { useFormikContext } from "formik";
import { useCallback } from "react";
import { Form } from "react-bootstrap";
import Select, { Options } from "react-select";
import { ISelectOption, sway } from "sway";

const SelectField: React.FC<IFieldProps> = ({ swayField, fieldGroupLength }) => {
    const { values, setFieldValue } = useFormikContext();
    const [locale] = useLocale();
    const assignPossibleValues = useAssignValues();

    const isRenderPositionsSelects = useCallback(
        (field: sway.IFormField) => {
            if (["supporters", "opposers", "abstainers"].includes(field.name)) {
                return locale.name !== CONGRESS_LOCALE_NAME;
            } else {
                return true;
            }
        },
        [locale.name],
    );

    swayField.possibleValues = assignPossibleValues(swayField);

    const getValue = (v: any) => {
        if (Array.isArray(v)) {
            return val.map((_v: any) => getValue(_v));
        } else if (["string", "number"].includes(typeof v)) {
            return (swayField.possibleValues || []).find((item) => item.value === v);
        } else {
            return v;
        }
    };

    const { name } = swayField;
    const val = (values as Record<string, any>)[swayField.name];
    const value = getValue(val);

    return (
        <Form.Group
            key={name}
            controlId={name}
            className={`col-xs-12 col-sm-${swayField.colClass || (12 / fieldGroupLength >= 4 ? 12 / fieldGroupLength : 4)}`}
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
                    setFieldValue(name, changed).catch(console.error);
                }}
                closeMenuOnSelect={!["supporters", "opposers", "abstainers"].includes(name)}
            />
        </Form.Group>
    );
};

export default SelectField;
