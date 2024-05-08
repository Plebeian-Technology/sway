/* eslint-disable react-hooks/exhaustive-deps */

/** @format */
import { CONGRESS_LOCALE_NAME, ESwayLevel, Support } from "app/frontend/sway_constants";
import { isCongressLocale, isEmptyObject, logDev, titleize, toFormattedLocaleName } from "app/frontend/sway_utils";
import { Formik, Form as FormikForm, FormikProps } from "formik";
import { get, sortBy } from "lodash";
import { useCallback, useMemo, useRef, useState } from "react";
import { Button, Form } from "react-bootstrap";
import DatePicker from "react-datepicker";
import "react-datepicker/dist/react-datepicker.css";
import { FiSave } from "react-icons/fi";
import Select, { MultiValue, Options, SingleValue } from "react-select";
import { ISelectOption, sway } from "sway";
import * as Yup from "yup";
import { useCancellable } from "../hooks/useCancellable";
import { useLegislatorVotes } from "../hooks/useLegislatorVotes";

import { useAxiosGet, useAxiosPost } from "app/frontend/hooks/useAxios";
import { useLocale } from "app/frontend/hooks/useLocales";
import { getDateFromString } from "app/frontend/sway_utils/datetimes";
import BillCreatorOrganizations from "../components/admin/BillCreatorOrganizations";
import BillCreatorSummaryAudio from "../components/admin/BillCreatorSummaryAudio";
import BillOfTheWeekCreatorPreview from "../components/admin/BillOfTheWeekCreatorPreview";
import { IDataOrganizationPosition } from "../components/admin/types";
import BillCreatorSummary from "../components/bill/BillCreatorSummary";
import { BILL_INPUTS } from "../components/bill/creator/inputs";
import FullScreenLoading from "../components/dialogs/FullScreenLoading";
import SwaySelect from "../components/forms/SwaySelect";
import SwayText from "../components/forms/SwayText";
import SwayTextArea from "../components/forms/SwayTextArea";
import SwaySpinner from "../components/SwaySpinner";
import { handleError, notify, REACT_SELECT_STYLES, toSelectOption } from "../sway_utils";

const VALIDATION_SCHEMA = Yup.object().shape({
    externalId: Yup.string().required(),
    externalVersion: Yup.string(),
    title: Yup.string().required(),
    link: Yup.string().required().url(),
    summary: Yup.string(),
    legislatorId: Yup.string().required(),
    localeName: Yup.string().required(),
    legislators: Yup.object().required(),
    swayAudioBucketPath: Yup.string().nullable().notRequired(),
});

type ISubmitValues = sway.IBill & {
    supporters: number[];
    opposers: number[];
    abstainers: number[];

    // organizations: IDataOrganizationPosition[];

    swayAudioBucketPath?: string;
    swayAudioByline?: string;

    // positions: {
    //     [organizationName: string]: {
    //         name: string;
    //         iconPath: string;
    //         positions: {
    //             [billExternalId: string]: {
    //                 billExternalId: string;
    //                 support: boolean;
    //                 summary: string;
    //             };
    //         };
    //     };
    // };
};

const DEFAULT_BILL_ID = "new-botw";
const DEFAULT_LEGISLATORS = [] as sway.ILegislator[];
const DEFAULT_ORGANIZATIONS = [] as sway.IOrganization[];

interface IProps {
    bill: sway.IBill;
    bills: sway.IBill[];
}

const BillOfTheWeekCreator: React.FC<IProps> = ({ bill }) => {
    const makeCancellable = useCancellable();
    const summaryRef = useRef<string>("");
    const [locale] = useLocale();
    // const { isAdmin } = user;
    const isAdmin = true;
    const {
        items: legislatorVotes,
        get: getLegislatorVotes,
        isLoading: isLoadingLegislatorVotes,
    } = useLegislatorVotes();

    const { items: bills } = useAxiosGet<sway.IBill[]>("/bills", { skipInitialRequest: false, notifyOnValidationResultFailure: true })
    const { items: legislators } = useAxiosGet<sway.ILegislator[]>("/legislators", { skipInitialRequest: false, notifyOnValidationResultFailure: true })
    const { post: createBill } = useAxiosPost<sway.IBill>("/bills");
    const { post: createLegislatorVotes } = useAxiosPost<sway.ILegislatorVote[]>("/legislator_votes");
    const { post: createOrganization } = useAxiosPost<sway.IOrganization>("/organizations");
    const { post: createOrganizationBillPosition } = useAxiosPost<sway.IOrganizationPosition>("/organizations");

    const [isLoading, setLoading] = useState<boolean>(false);
    const [selectedBill, setSelectedBill] = useState<ISelectOption>({ label: `${bill.externalId} - ${bill.title}`, value: bill.id });
    const [organizations, setOrganizations] = useState<sway.IOrganization[]>(DEFAULT_ORGANIZATIONS);

    const options = useMemo(() => (bills ?? []).map((b) => ({ label: `${b.externalId} - ${b.title}`, value: b.id })), [bills]);

    const legislatorOptions = useMemo(
        () =>
            sortBy(
                (legislators ?? []).map((l: sway.ILegislator) =>
                    toSelectOption(
                        `${titleize(l.lastName)}, ${titleize(l.firstName)} (${l.district.regionCode} - ${
                            l.district.number
                        })`,
                        l.externalId,
                    ),
                ),
                ["label"],
            ),
        [legislators],
    );


    const handleSubmit = (
        values: ISubmitValues,
        { setSubmitting }: { setSubmitting: (_isSubmitting: boolean) => void },
    ) => {
        logDev("BillOfTheWeekCreator.handleSubmit - SUBMITTING - new bill of the week - VALUES + SUMMARY REF", {
            values,
            summaryRef: summaryRef.current,
        });
        if (!isAdmin || !legislators) return;

        try {
            if (!summaryRef.current) {
                notify({
                    level: "warning",
                    title: "Sway summary is required.",
                });
                setSubmitting(false);
                return;
            }

            if (!legislators.map((l) => l.id).includes(values.legislatorId)) {
                notify({
                    level: "error",
                    title: "Invalid Sponsor",
                    message: "Sponsor is not a valid legislator. Wrong locale?",
                });
                setSubmitting(false);
                return;
            }

            const voteLegislatorIds = values.supporters.concat(values.opposers).concat(values.abstainers).flat();

            if (voteLegislatorIds.length > legislators.length) {
                const dupes = voteLegislatorIds.filter((id: number, index: number) => {
                    return voteLegislatorIds.lastIndexOf(id) !== index;
                });
                notify({
                    level: "error",
                    title: "Duplicate Legislator Positions",
                    message: `Legislators - ${dupes.join(", ")} - are duplicated in multiple positions.`,
                });
                logDev("BillOfTheWeekCreator.handleSubmit - DUPLICATE LEGISLATOR POSITION -", dupes);
                setSubmitting(false);
                return;
            }

            const votedate = values.houseVoteDateTimeUtc || values.senateVoteDateTimeUtc

            if (!isCongressLocale(locale) && voteLegislatorIds.length !== legislators.length) {
                const missing = legislators.filter((l) => !voteLegislatorIds.includes(l.id));
                notify({
                    level: votedate ? "error" : "warning",
                    title: votedate ? "Legislators Missing" : "IGNORING Missing Legislators - No Vote Date",
                    message: `Legislators - ${missing.map((l) => l.externalId).join(", ")} - are missing support.`,
                });
                logDev("BillOfTheWeekCreator.handleSubmit - MISSING LEGISLATOR -", missing);
                if (votedate) {
                    setSubmitting(false);
                    return;
                }
            }

            logDev("BillOfTheWeekCreator.handleSubmit - VALUES", values);

            createBill(values)
                .then((result) => {
                    if (result) {
                        createLegislatorVotes(
                            [
                                ...values.supporters.map((id) => ({
                                    legislator_id: id,
                                    bill_id: result.id,
                                    support: Support.For,
                                })),
                                ...values.opposers.map((id) => ({
                                    legislator_id: id,
                                    bill_id: result.id,
                                    support: Support.Against,
                                })),
                                ...values.abstainers.map((id) => ({
                                    legislator_id: id,
                                    bill_id: result.id,
                                    support: Support.Abstain,
                                })),
                            ].flat(),
                        ).catch(handleError);
                    }
                })
                .catch(handleError);

            // setSubmitting(true);
            // const setter = httpsCallable(functions, CLOUD_FUNCTIONS.createBill);
            // setter(values)
            //     .then((response) => {
            //         if (
            //             (response as HttpsCallableResult<sway.ICloudFunctionResponse>).data.success
            //         ) {
            //             notify({
            //                 level: "success",
            //                 title: "Bill of the Week Created.",
            //                 message: "Created bill of the week",
            //             });
            //         } else {
            //             notify({
            //                 level: "error",
            //                 title: "Error",
            //                 message: "Failed to create bill of the week",
            //             });
            //         }
            //         setSubmitting(false);
            //     })
            //     .catch((error: Error) => {
            //         logDev(
            //             "BillOfTheWeekCreator.handleSubmit - ERROR - setting bill of the week in firebase",
            //         );
            //         handleError(error);
            //         setSubmitting(false);
            //     });
        } catch (e) {
            console.error(e);
            setSubmitting(false);
        }
    };

    const generateValues = useCallback((field: sway.IFormField, values: ISubmitValues) => {
        if (field.component === "generatedText" && field.generateFields) {
            return field.generateFields
                .map((fieldname: string) => (values as Record<string, any>)[fieldname])
                .join(field.joiner || " ");
        }
        return "";
    }, []);

    const assignPossibleValues = (field: sway.IFormField, values?: ISubmitValues): sway.TOption[] => {
        if (field.name === "legislatorId") {
            return legislatorOptions;
        } else if (field.name === "chamber") {
            if (isCongressLocale(locale)) {
                return [toSelectOption("house", "house"), toSelectOption("senate", "senate")];
            } else {
                return [toSelectOption("council", "council")];
            }
        } else if (field.name === "organizations") {
            return organizations.map((o) => ({
                label: o.name,
                value: o.name,
                iconPath: o.iconPath,
                support: get(o.positions, bill.id),
            }));
        } else if (["supporters", "opposers", "abstainers"].includes(field.name)) {
            const selectedSupporterIds = get(values, "supporters") || [];
            const selectedOpposerIds = get(values, "opposers") || [];
            const selectedAbstainerIds = get(values, "abstainers") || [];
            const selected = selectedSupporterIds.concat(selectedOpposerIds).concat(selectedAbstainerIds);

            return legislatorOptions.filter((o) => !selected.includes(o.value as number));
        } else {
            return field.possibleValues || [];
        }
    };

    const initialBill = {
        id: bill.id,
        externalId: bill?.externalId?.trim() || "",
        externalVersion: bill?.externalVersion?.trim() || "",
        title: bill?.title?.trim() || "",
        link: bill?.link?.trim() || "",
        legislatorId: bill?.legislatorId || -1,
        chamber: bill?.chamber || (isCongressLocale(locale) ? "house" : "council"),
        level: bill?.level?.trim() || ESwayLevel.Local,
        summary: bill?.summary?.trim(),
        introducedDateTimeUtc: getDateFromString(bill?.introducedDateTimeUtc),
        houseVoteDateTimeUtc: isCongressLocale(locale) ? getDateFromString(bill.houseVoteDateTimeUtc) : undefined,
        senateVoteDateTimeUtc: isCongressLocale(locale) ? getDateFromString(bill.senateVoteDateTimeUtc) : undefined,
        category: bill?.category?.trim(),

        // TODO
        // active: bill?.active || true,
        // swayAudioBucketPath: bill?.swayAudioBucketPath?.trim() || "",
        // swayAudioByline: bill?.swayAudioByline?.trim() || "",
    };

    const initialValues = {
        ...initialBill,
        supporters: (legislatorVotes?.filter((lv) => lv.support === Support.For).map(lv => lv.legislatorId) || []),
        opposers: (legislatorVotes?.filter((lv) => lv.support === Support.Against).map(lv => lv.legislatorId) || []),
        abstainers: (legislatorVotes?.filter((lv) => lv.support === Support.Abstain).map(lv => lv.legislatorId) || []),
    } as ISubmitValues;

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

    const renderFields = (formik: FormikProps<ISubmitValues>) => {
        const { values, touched, errors, setFieldValue, setTouched } = formik;
        if (!isEmptyObject(errors)) {
            logDev("BillOfTheWeekCreator.renderFields - ERRORS", errors);
        }

        logDev("BillOfTheWeekCreator.renderFields - VALUES -", values);

        const handleSetTouched = (fieldname: string) => {
            if ((touched as Record<string, any>)[fieldname]) return;
            setTouched({
                ...touched,
                [fieldname]: true,
            }).catch(console.error);
        };

        const errorMessage = (fieldname: string): string => {
            if (!fieldname || !errors || !(touched as Record<string, any>)[fieldname]) return "";

            const error = get(errors, fieldname);
            if (!error) return "";

            if (Array.isArray(error)) {
                return (error as string[]).find((e) => e === fieldname) || "";
            } else {
                return error as string;
            }
        };

        const render = [] as React.ReactNode[];
        let i = 0;
        while (i < BILL_INPUTS.length) {
            const fieldGroup = BILL_INPUTS[i];

            const row = [];
            for (const field of fieldGroup) {
                const generatedValue = generateValues(field, values);

                const { component } = field;

                if (["houseVoteDate", "senateVoteDate"].includes(field.name) && !isCongressLocale(locale)) {
                    continue;
                }

                if (["text", "generatedText"].includes(component)) {
                    const value = component === "text" ? (values as Record<string, any>)[field.name] : generatedValue;

                    row.push(
                        <div key={field.name} className="col">
                            <SwayText
                                field={{
                                    ...field,
                                    disabled: Boolean(field.disabled || field.disableOn?.(locale)),
                                }}
                                value={value}
                                error={errorMessage(field.name)}
                                helperText={field.helperText}
                            />
                        </div>,
                    );
                } else if (component === "select") {
                    if (field.name === "organizations") {
                        field.possibleValues = assignPossibleValues(field);
                        row.push(
                            <div key={field.name} className="col-12 py-4">
                                <BillCreatorOrganizations
                                    field={{
                                        ...field,
                                        disabled: Boolean(field.disabled || field.disableOn?.(locale)),
                                    }}
                                    organizations={(values as Record<string, any>)[field.name]}
                                    touched={!!(touched as Record<string, any>)[field.name]}
                                    error={errors[field.name] as string | undefined}
                                    setFieldValue={setFieldValue}
                                    handleSetTouched={handleSetTouched}
                                    billExternalId={values.externalId}
                                />
                            </div>,
                        );
                    } else if (field.name === "localeName") {
                        row.push(
                            <div key={field.name} className="col">
                                <SwaySelect
                                    field={field}
                                    error={errorMessage(field.name)}
                                    handleSetTouched={() => null}
                                    setFieldValue={(fname, fvalue) => {
                                        setFieldValue(fname, fvalue).catch(console.error);
                                    }}
                                    value={toSelectOption(toFormattedLocaleName(locale.name), locale.id)}
                                    helperText={field.helperText}
                                />
                            </div>,
                        );
                    } else {
                        field.possibleValues = assignPossibleValues(field, values);
                        const val = (values as Record<string, any>)[field.name];
                        const { name } = field;
                        const value = Array.isArray(val)
                            ? val.map((v) => toSelectOption(v, v))
                            : val
                              ? toSelectOption(val as string, val as string)
                              : toSelectOption(`Select ${field.label.toLowerCase()}...`, "");

                        logDev("SwaySelect.value", { name, val, value });
                        row.push(
                            <Form.Group key={name} controlId={name} className="col">
                                {field.label && (
                                    <Form.Label className="bold">
                                        {field.label}
                                        {field.isRequired ? " *" : " (Optional)"}
                                    </Form.Label>
                                )}
                                <Select
                                    name={name}
                                    styles={REACT_SELECT_STYLES}
                                    options={field.possibleValues as Options<sway.TOption>}
                                    isMulti={Boolean(field.multi)}
                                    isDisabled={
                                        !isRenderPositionsSelects(field) || field.disabled || field.disableOn?.(locale)
                                    }
                                    value={value}
                                    onChange={(changed) => {
                                        if (field.multi) {
                                            setFieldValue(
                                                name,
                                                (changed as MultiValue<sway.TOption>).map((c) => c.value),
                                            ).catch(console.error);
                                        } else {
                                            setFieldValue(name, (changed as SingleValue<sway.TOption>)?.value).catch(
                                                console.error,
                                            );
                                        }
                                    }}
                                    closeMenuOnSelect={!["supporters", "opposers", "abstainers"].includes(name)}
                                />
                            </Form.Group>,
                        );
                    }
                } else if (field.name === "summary") {
                    row.push(
                        <Form.Group key={field.name} controlId={field.name} className="col">
                            <Form.Label className="bold">
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <BillCreatorSummary
                                ref={summaryRef}
                                field={{
                                    ...field,
                                    disabled: Boolean(field.disabled || field.disableOn?.(locale)),
                                }}
                            />
                            <BillCreatorSummaryAudio setFieldValue={setFieldValue} />
                        </Form.Group>,
                    );
                } else if (field.name === "summaryPreview") {
                    // noop
                } else if (component === "textarea") {
                    row.push(
                        <Form.Group key={field.name} controlId={field.name} className="col">
                            <Form.Label className="bold">
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <SwayTextArea
                                field={{
                                    ...field,
                                    disabled: Boolean(field.disabled || field.disableOn?.(locale)),
                                }}
                                value={(values as Record<string, any>)[field.name]}
                                error={errorMessage(field.name)}
                                setFieldValue={setFieldValue}
                                handleSetTouched={handleSetTouched}
                                helperText={field.helperText}
                                rows={field.rows}
                            />
                        </Form.Group>,
                    );
                } else if (component === "date") {
                    row.push(
                        <Form.Group key={field.name} controlId={field.name} className="col">
                            <Form.Label className="bold">
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <DatePicker
                                className="form-control"
                                placeholderText={"Select date..."}
                                disabled={field.disabled || field.disableOn?.(locale)}
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
                                selected={(values as Record<string, any>)[field.name]}
                                onChange={(changed: Date) => {
                                    setFieldValue(field.name, changed).catch(console.error);
                                }}
                            />
                            {field.helperText && <div className="text-muted">{field.helperText}</div>}
                            <div className="text-danger">{errorMessage(field.name)}</div>
                        </Form.Group>,
                    );
                }
            }
            render.push(
                <div key={`row-${render.length}`} className="row my-5 border rounded p-3">
                    {row}
                </div>,
            );
            i++;
        }
        return render;
    };

    const handleChangeBill = useCallback((o: SingleValue<ISelectOption>) => {
        if (o) {
            setSelectedBill(o.value);
        }
    }, []);

    if (!isAdmin || !locale) {
        logDev("BillOfTheWeekCreator - no admin OR no locale - render null");
        return null;
    }

    return (
        <div className="col">
            {isLoading && <FullScreenLoading message="Loading..." />}
            <Formik
                initialValues={initialValues}
                validationSchema={VALIDATION_SCHEMA}
                onSubmit={handleSubmit}
                enableReinitialize={true}
                onReset={() => logDev("RESET FORMIK")}
            >
                {(formik) => {
                    return (
                        <>
                            <FormikForm>
                                <Form.Group controlId="selectedBill">
                                    <Form.Label className="bold">Previous Bill of the Day</Form.Label>
                                    <Select
                                        name="selectedBill"
                                        options={options}
                                        value={selectedBill}
                                        onChange={handleChangeBill}
                                    />
                                </Form.Group>
                                <hr />
                                {renderFields(formik)}
                                <div className="mx-auto text-center p-5">
                                    <div className="row align-items-center">
                                        <div className="col text-center">
                                            <Button
                                                disabled={formik.isSubmitting}
                                                variant="primary"
                                                size="lg"
                                                type="submit"
                                                className="p-5 w-50"
                                            >
                                                <FiSave />
                                                &nbsp;Save
                                            </Button>
                                        </div>
                                    </div>
                                    <div className="row align-items-center mt-3">
                                        <div className="col text-center">
                                            <SwaySpinner isHidden={!formik.isSubmitting} />
                                        </div>
                                    </div>
                                </div>
                            </FormikForm>
                            <BillOfTheWeekCreatorPreview
                                bill={formik.values}
                                organizations={formik.values.organizations}
                                summary={summaryRef.current}
                            />
                        </>
                    );
                }}
            </Formik>
        </div>
    );
};

export default BillOfTheWeekCreator;
