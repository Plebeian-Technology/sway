import SwayLogo from "app/frontend/components/SwayLogo";
import BillCreatorOrganizations from "app/frontend/components/admin/BillCreatorOrganizations";
import { ISubmitValues } from "app/frontend/components/admin/types";
import BillCreatorSummary from "app/frontend/components/bill/BillCreatorSummary";
import { BILL_INPUTS } from "app/frontend/components/bill/creator/inputs";
import SwaySelect from "app/frontend/components/forms/SwaySelect";
import SwayText from "app/frontend/components/forms/SwayText";
import SwayTextArea from "app/frontend/components/forms/SwayTextArea";
import { useLocale } from "app/frontend/hooks/useLocales";
import { CONGRESS_LOCALE_NAME } from "app/frontend/sway_constants";
import {
    REACT_SELECT_STYLES,
    isCongressLocale,
    logDev,
    titleize,
    toFormattedLocaleName,
    toSelectOption,
} from "app/frontend/sway_utils";
import { useFormikContext } from "formik";
import { get, isEmpty, sortBy } from "lodash";
import { forwardRef, useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";
import DatePicker from "react-datepicker";
import Select, { Options } from "react-select";
import { ISelectOption, sway } from "sway";

interface IProps {
    legislators: sway.ILegislator[];
}

const BillCreatorFields = forwardRef(({ legislators }: IProps, summaryRef: React.Ref<string>) => {
    const [locale] = useLocale();

    const { values, touched, errors, setFieldValue, setTouched } = useFormikContext<ISubmitValues>();

    if (!isEmpty(errors)) {
        logDev("BillOfTheWeekCreator.renderFields - ERRORS", errors);
    }

    // logDev("BillOfTheWeekCreator.renderFields - VALUES -", values);

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

            if (Array.isArray(error)) {
                return (error as string[]).find((e) => e === fieldname) || "";
            } else {
                return error as string;
            }
        },
        [errors, touched],
    );

    const generateValues = useCallback(
        (swayField: sway.IFormField) => {
            if (swayField.component === "generatedText" && swayField.generateFields) {
                return swayField.generateFields
                    .map((fieldname: string) => (values as Record<string, any>)[fieldname])
                    .join(swayField.joiner || " ");
            }
            return "";
        },
        [values],
    );

    const legislatorOptions = useMemo(
        () =>
            sortBy(
                (legislators ?? []).map((l: sway.ILegislator) => ({
                    label: `${titleize(l.lastName)}, ${titleize(l.firstName)} (${l.district.regionCode} - ${
                        l.district.number
                    })`,
                    value: l.id,
                })),
                ["label"],
            ),
        [legislators],
    );

    const assignPossibleValues = useCallback(
        (swayField: sway.IFormField): ISelectOption[] => {
            if (swayField.name === "legislator") {
                return legislatorOptions;
            } else if (swayField.name === "chamber") {
                if (isCongressLocale(locale)) {
                    return [toSelectOption("house", "house"), toSelectOption("senate", "senate")];
                } else {
                    return [toSelectOption("council", "council")];
                }
            } else if (["supporters", "opposers", "abstainers"].includes(swayField.name)) {
                const selectedSupporter = get(values, "supporters") || [];
                const selectedOpposer = get(values, "opposers") || [];
                const selectedAbstainer = get(values, "abstainers") || [];
                const selected = selectedSupporter.concat(selectedOpposer).concat(selectedAbstainer);

                return legislatorOptions.filter((o) => !selected.find((s) => s.value === o.value));
            } else {
                return swayField.possibleValues || [];
            }
        },
        [legislatorOptions, locale, values],
    );

    const isRenderPositionsSelects = useCallback(
        (swayField: sway.IFormField) => {
            if (["supporters", "opposers", "abstainers"].includes(swayField.name)) {
                return locale.name !== CONGRESS_LOCALE_NAME;
            } else {
                return true;
            }
        },
        [locale.name],
    );

    return useMemo(() => {
        const render = [] as React.ReactNode[];
        let i = 0;
        while (i < BILL_INPUTS.length) {
            const fieldGroup = BILL_INPUTS[i];

            const row = [];
            for (const swayField of fieldGroup) {
                const generatedValue = generateValues(swayField);

                const { component } = swayField;

                if (swayField.name === "senateVoteDateTimeUtc" && !isCongressLocale(locale)) {
                    continue;
                }

                if (component === "separator") {
                    row.push(
                        <div key={swayField.name} className="text-center my-5">
                            <SwayLogo />
                        </div>,
                    );
                } else if (["text", "generatedText"].includes(component)) {
                    const value =
                        component === "text" ? (values as Record<string, any>)[swayField.name] : generatedValue;

                    row.push(
                        <div key={swayField.name} className="col">
                            <SwayText
                                field={{
                                    ...swayField,
                                    disabled: Boolean(swayField.disabled || swayField.disableOn?.(locale)),
                                }}
                                value={value}
                                error={errorMessage(swayField.name)}
                                helperText={swayField.helperText}
                            />
                        </div>,
                    );
                } else if (component === "select") {
                    if (swayField.name.startsWith("organizations")) {
                        row.push(
                            <div key={swayField.name} className="col-12 py-4">
                                <BillCreatorOrganizations
                                    swayFieldName={swayField.name}
                                    error={(errors as Record<string, any>)[swayField.name] as string | undefined}
                                    handleSetTouched={handleSetTouched}
                                />
                            </div>,
                        );
                    } else if (swayField.name === "localeName") {
                        row.push(
                            <div key={swayField.name} className="col">
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
                            </div>,
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

                        // logDev("SwaySelect.values", { val, value, name, possibleValues: swayField.possibleValues });

                        row.push(
                            <Form.Group key={name} controlId={name} className="col">
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
                            </Form.Group>,
                        );
                    }
                } else if (swayField.name === "summary") {
                    row.push(
                        <Form.Group key={swayField.name} controlId={swayField.name} className="col">
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
                            {/* TODO */}
                            {/* <BillCreatorSummaryAudio setFieldValue={setFieldValue} /> */}
                        </Form.Group>,
                    );
                } else if (swayField.name === "summaryPreview") {
                    // noop
                } else if (component === "textarea") {
                    row.push(
                        <Form.Group key={swayField.name} controlId={swayField.name} className="col">
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
                        </Form.Group>,
                    );
                } else if (component === "date") {
                    row.push(
                        <Form.Group key={swayField.name} controlId={swayField.name} className="col">
                            <Form.Label className="bold my-0">
                                {swayField.label}
                                {swayField.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <div className="my-2">
                                <DatePicker
                                    className="form-control"
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
                                    onChange={(changed: Date) => {
                                        setFieldValue(swayField.name, changed).catch(console.error);
                                    }}
                                />
                            </div>
                            {swayField.helperText && <div className="text-muted">{swayField.helperText}</div>}
                            <div className="text-danger">{errorMessage(swayField.name)}</div>
                        </Form.Group>,
                    );
                }
            }

            render.push(
                <div
                    key={`row-${render.length}`}
                    className={`row my-3 p-3 ${fieldGroup.first().component === "separator" ? "" : "border rounded"}`}
                >
                    {row}
                </div>,
            );

            i++;
        }
        return render;
    }, [
        assignPossibleValues,
        errorMessage,
        errors,
        generateValues,
        handleSetTouched,
        isRenderPositionsSelects,
        locale,
        setFieldValue,
        summaryRef,
        values,
    ]);
});

export default BillCreatorFields;
