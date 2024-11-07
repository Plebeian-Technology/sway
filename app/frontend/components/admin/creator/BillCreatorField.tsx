import BillCreatorOrganizations from "app/frontend/components/admin/BillCreatorOrganizations";
import BillCreatorSummaryAudio from "app/frontend/components/admin/BillCreatorSummaryAudio";
import { ISubmitValues } from "app/frontend/components/admin/types";
import BillCreatorSummary from "app/frontend/components/bill/BillCreatorSummary";
import SwaySelect from "app/frontend/components/forms/SwaySelect";
import SwayText from "app/frontend/components/forms/SwayText";
import SwayTextArea from "app/frontend/components/forms/SwayTextArea";
import SwayLogo from "app/frontend/components/SwayLogo";
import { useLocale } from "app/frontend/hooks/useLocales";
import {
    isCongressLocale,
    logDev,
    REACT_SELECT_STYLES,
    toFormattedLocaleName,
    toSelectOption,
} from "app/frontend/sway_utils";
import { useFormikContext } from "formik";

import { CONGRESS_LOCALE_NAME } from "app/frontend/sway_constants";
import { get } from "lodash";
import { forwardRef, useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";
import DatePicker from "react-datepicker";
import Select, { Options } from "react-select";
import { ISelectOption, sway } from "sway";

interface IProps {
    swayField: sway.IFormField;
    fieldGroup: sway.IFormField[];
    assignPossibleValues: (field: sway.IFormField) => ISelectOption[];
}

const BillCreatorField = forwardRef(
    ({ swayField, fieldGroup, assignPossibleValues }: IProps, summaryRef: React.Ref<string>) => {
        const [locale] = useLocale();

        const { values, errors, setFieldValue, touched, setTouched } = useFormikContext<ISubmitValues>();

        const handleSetTouched = useCallback(
            (fieldname: string) => {
                if ((touched as Record<string, any>)[fieldname]) return;
                setTouched({
                    ...touched,
                    [fieldname]: true,
                }).catch(console.error);
            },
            [setTouched, touched],
        );

        const errorMessage = useCallback(
            (fieldname: string): string => {
                if (!fieldname || !errors || !(touched as Record<string, any>)[fieldname]) return "";

                const error = get(errors, fieldname);
                if (!error) return "";

                logDev("BillCreatorField.errorMessage -", { error, fieldname });

                if (Array.isArray(error)) {
                    return (error as string[]).find((e) => e === fieldname) || "";
                } else {
                    return error as string;
                }
            },
            [errors, touched],
        );

        const generatedValue = useMemo(() => {
            if (swayField.component === "generatedText" && swayField.generateFields) {
                return swayField.generateFields
                    .map((fieldname: string) => (values as Record<string, any>)[fieldname])
                    .join(swayField.joiner || " ");
            }
            return "";
        }, [values, swayField]);

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

        const { component } = swayField;

        if (swayField.name === "senateVoteDateTimeUtc" && !isCongressLocale(locale)) {
            return null;
        }

        if (component === "separator") {
            return (
                <div key={swayField.name} className="text-center my-5">
                    <SwayLogo />
                </div>
            );
        } else if (["text", "generatedText"].includes(component)) {
            const value = component === "text" ? (values as Record<string, any>)[swayField.name] : generatedValue;

            return (
                <div key={swayField.name} className={`col-${12 / fieldGroup.length >= 4 ? 12 / fieldGroup.length : 4}`}>
                    <SwayText
                        field={{
                            ...swayField,
                            disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
                        }}
                        value={value}
                        error={errorMessage(swayField.name)}
                        helperText={swayField.helperText}
                    />
                </div>
            );
        } else if (component === "select") {
            if (swayField.name.startsWith("organizations")) {
                return (
                    <div key={swayField.name} className="col-12 py-4">
                        <BillCreatorOrganizations
                            swayFieldName={swayField.name}
                            error={(errors as Record<string, any>)[swayField.name] as string | undefined}
                            handleSetTouched={handleSetTouched}
                        />
                    </div>
                );
            } else if (swayField.name === "localeName") {
                return (
                    <div
                        key={swayField.name}
                        className={`col-${12 / fieldGroup.length >= 4 ? 12 / fieldGroup.length : 4}`}
                    >
                        <SwaySelect
                            field={swayField}
                            error={errorMessage(swayField.name)}
                            handleSetTouched={() => null}
                            setFieldValue={(fname, fvalue) => {
                                setFieldValue(fname, fvalue).catch(console.error);
                            }}
                            value={toSelectOption(toFormattedLocaleName(locale.name), locale.id)}
                            helperText={swayField.helperText}
                        />
                    </div>
                );
            } else {
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
                        className={`col-${12 / fieldGroup.length >= 4 ? 12 / fieldGroup.length : 4}`}
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
                            isDisabled={
                                !isRenderPositionsSelects(swayField) ||
                                swayField.disabled ||
                                swayField.disableOn?.(locale)
                            }
                            value={value}
                            onChange={(changed) => {
                                setFieldValue(name, changed).catch(console.error);
                            }}
                            closeMenuOnSelect={!["supporters", "opposers", "abstainers"].includes(name)}
                        />
                    </Form.Group>
                );
            }
        } else if (swayField.name === "summary") {
            return (
                <Form.Group key={swayField.name} controlId={swayField.name} className={"col"}>
                    <Form.Label className="bold">
                        {swayField.label}
                        {swayField.isRequired ? " *" : " (Optional)"}
                    </Form.Label>
                    <BillCreatorSummary
                        ref={summaryRef}
                        field={{
                            ...swayField,
                            disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
                        }}
                    />
                    <BillCreatorSummaryAudio setFieldValue={setFieldValue} />
                </Form.Group>
            );
        } else if (swayField.name === "summaryPreview") {
            // noop
        } else if (component === "textarea") {
            return (
                <Form.Group
                    key={swayField.name}
                    controlId={swayField.name}
                    className={`col-${12 / fieldGroup.length >= 4 ? 12 / fieldGroup.length : 4}`}
                >
                    <Form.Label className="bold">
                        {swayField.label}
                        {swayField.isRequired ? " *" : " (Optional)"}
                    </Form.Label>
                    <SwayTextArea
                        field={{
                            ...swayField,
                            disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
                        }}
                        value={(values as Record<string, any>)[swayField.name]}
                        error={errorMessage(swayField.name)}
                        setFieldValue={setFieldValue}
                        handleSetTouched={handleSetTouched}
                        helperText={swayField.helperText}
                        rows={swayField.rows}
                    />
                </Form.Group>
            );
        } else if (component === "date") {
            return (
                <Form.Group
                    key={swayField.name}
                    controlId={swayField.name}
                    className={`col-${12 / fieldGroup.length >= 4 ? 12 / fieldGroup.length : 4}`}
                >
                    <Form.Label className="bold my-0">
                        {swayField.label}
                        {swayField.isRequired ? " *" : " (Optional)"}
                    </Form.Label>
                    <div className="my-2">
                        <DatePicker
                            className="form-control z-100"
                            calendarClassName="z-100"
                            wrapperClassName="z-100"
                            placeholderText={"Select date..."}
                            disabled={swayField.disabled || swayField.disableOn?.(locale)}
                            minDate={(() => {
                                const date = new Date();
                                date.setFullYear(date.getFullYear() - 1);
                                return date;
                            })()}
                            maxDate={(() => {
                                const date = new Date();
                                date.setHours(date.getHours() + 24);
                                return date;
                            })()}
                            selected={(values as Record<string, any>)[swayField.name]}
                            onChange={(changed: Date | null) => {
                                if (changed) {
                                    setFieldValue(swayField.name, changed).catch(console.error);
                                }
                            }}
                        />
                    </div>
                    {swayField.helperText && <div className="text-muted">{swayField.helperText}</div>}
                    <div className="text-danger">{errorMessage(swayField.name)}</div>
                </Form.Group>
            );
        }
    },
);

export default BillCreatorField;
