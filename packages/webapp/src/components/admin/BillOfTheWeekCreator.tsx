/** @format */
import DatePicker from "react-datepicker";

import { CLOUD_FUNCTIONS, ESwayLevel, LOCALES, Support } from "@sway/constants";
import {
    get,
    isEmptyObject,
    logDev,
    toFormattedLocaleName,
    toFormattedNameFromExternalId,
} from "@sway/utils";
import { httpsCallable, HttpsCallableResult } from "firebase/functions";
import { Form as FormikForm, Formik, FormikProps } from "formik";
import { useCallback, useEffect, useRef } from "react";
import { Button, Form } from "react-bootstrap";
import "react-datepicker/dist/react-datepicker.css";
import { FiSave } from "react-icons/fi";
import Select, { MultiValue, Options, SingleValue } from "react-select";
import { sway } from "sway";
import * as Yup from "yup";
import { functions } from "../../firebase";
import { useUserWithSettingsAdmin } from "../../hooks";
import { EUseBillsFilters, useBills } from "../../hooks/bills";
import { useCancellable } from "../../hooks/cancellable";
import { useImmer } from "../../hooks/useImmer";
import { useLegislatorVotes } from "../../hooks/useLegislatorVotes";
import {
    handleError,
    notify,
    REACT_SELECT_STYLES,
    swayFireClient,
    toSelectOption,
} from "../../utils";
import BillCreatorSummary from "../bill/BillCreatorSummary";
import { BILL_INPUTS } from "../bill/creator/inputs";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SwaySelect from "../forms/SwaySelect";
import SwayText from "../forms/SwayText";
import SwayTextArea from "../forms/SwayTextArea";
import SwaySpinner from "../SwaySpinner";
import BillCreatorOrganizations from "./BillCreatorOrganizations";
import BillOfTheWeekCreatorPreview from "./BillOfTheWeekCreatorPreview";
import { TDataOrganizationPositions } from "./types";

const VALIDATION_SCHEMA = Yup.object().shape({
    externalId: Yup.string().required(),
    externalVersion: Yup.string(),
    title: Yup.string().required(),
    link: Yup.string().required().url(),
    swaySummary: Yup.string(),
    sponsorExternalId: Yup.string().required(),
    localeName: Yup.string().required(),
    legislators: Yup.object().required(),
});

interface ICreatorValues {
    [fieldname: string]:
        | string
        | boolean
        | sway.TSwayLevel
        | sway.IBillScore
        | firebase.default.firestore.FieldValue
        | Record<string, unknown>
        | never[]
        | undefined;
}

interface ISubmitValues extends sway.IBill {
    localeName: string;
    supporters: string[];
    opposers: string[];
    abstainers: string[];
    legislators: sway.ILegislatorBillSupport;
    organizations: TDataOrganizationPositions;
}
interface IState {
    isLoading: boolean;
    locale: sway.ILocale;
    selectedPreviousBOTWId: string;
    legislators: sway.ILegislator[];
    organizations: sway.IOrganization[];
}

const BillOfTheWeekCreator: React.FC = () => {
    const makeCancellable = useCancellable();
    const summaryRef = useRef<string>("");
    const user = useUserWithSettingsAdmin();
    const admin = user.isAdmin;
    const [bills, getBills] = useBills([EUseBillsFilters.ORGANIZATIONS]);
    const [legislatorVotes, getLegislatorVotes] = useLegislatorVotes();
    const [state, setState] = useImmer<IState>({
        isLoading: false,
        locale: LOCALES[0],
        selectedPreviousBOTWId: "new-botw",
        legislators: [],
        organizations: [],
    });
    const selectedPreviousBOTW = (bills || []).find(
        (b) => b.bill.firestoreId === state.selectedPreviousBOTWId,
    ) as sway.IBillOrgsUserVoteScore;

    const previousBOTWOptions = [
        <option key={"new-botw"} value={"new-botw"}>
            New Bill of the Week
        </option>,
    ].concat(
        bills.map((b) => (
            <option
                key={b.bill.firestoreId}
                value={b.bill.firestoreId}
            >{`${b.bill.externalId} - ${b.bill.title}`}</option>
        )),
    );

    const legislatorIds = state.legislators.map((l: sway.ILegislator) => l.externalId);

    const startLoading = () => {
        setState((draft) => {
            draft.isLoading = true;
        });
    };
    const stopLoading = () => {
        setState((draft) => {
            draft.isLoading = false;
        });
    };

    useEffect(() => {
        logDev("BillOfTheWeekCreator.useEffect - set summary ref to summary from selected bill");
        summaryRef.current = selectedPreviousBOTW?.bill?.swaySummary || "";
    }, [selectedPreviousBOTW?.bill?.swaySummary]);

    useEffect(() => {
        logDev("BillOfTheWeekCreator.useEffect - get bills");
        startLoading();
        getBills(state.locale, user.user.uid, [])
            .then(stopLoading)
            .catch((error) => {
                stopLoading();
                handleError(error);
            });
    }, [state.locale, user.user.uid]);

    useEffect(() => {
        logDev("BillOfTheWeekCreator.useEffect - get legislator votes");

        if (selectedPreviousBOTW?.bill?.firestoreId && !isEmptyObject(legislatorIds)) {
            logDev("BillOfTheWeekCreator.useEffect - set legislator votes for selected bill");
            startLoading();
            getLegislatorVotes(legislatorIds, selectedPreviousBOTW.bill.firestoreId)
                .then(stopLoading)
                .catch((error) => {
                    stopLoading();
                    handleError(error);
                });
        }
    }, [selectedPreviousBOTW?.bill.firestoreId, isEmptyObject(legislatorIds)]);

    useEffect(() => {
        logDev("BillOfTheWeekCreator.useEffect.LOAD");

        if (!admin) {
            logDev("BillOfTheWeekCreator.useEffect - no admin, skip initializing");
            return;
        }

        if (!state.locale) {
            setState((draft) => {
                draft.locale = LOCALES[0];
            });
            logDev("BillOfTheWeekCreator.useEffect - set locale to LOCALES.first");
            return;
        }

        startLoading();

        const getOrganizations = async (): Promise<sway.IOrganization[]> => {
            if (!state.locale?.name) return [];

            const orgs = await swayFireClient(state.locale).organizations().list();
            logDev("BillOfTheWeekCreator.useEffect - get organizations");
            if (!orgs) return [];
            return orgs;
        };

        const getLegislators = async () => {
            if (!state.locale?.name) return [];
            logDev(
                "BillOfTheWeekCreator.useEffect - get legislators for locale -",
                state.locale.name,
            );
            const _legislators: (sway.ILegislator | undefined)[] = (await swayFireClient(
                state.locale,
            )
                .legislators()
                .list()) as sway.ILegislator[];
            return _legislators.filter(Boolean) as sway.ILegislator[];
        };

        const promise = makeCancellable(Promise.all([getOrganizations(), getLegislators()]), () =>
            logDev("BillOfTheWeekCreator.useEffect - canceled initialization"),
        );

        promise
            .then(([orgs, legs]) => {
                logDev("BillOfTheWeekCreator.useEffect - set organizations and legislators state");
                setState((draft) => {
                    draft.isLoading = false;
                    draft.organizations = orgs;
                    draft.legislators = legs;
                });
            })
            .catch((error) => {
                stopLoading();
                handleError(error);
            });
    }, [admin, state.locale.name]);

    if (!admin || !state.locale) {
        logDev("BillOfTheWeekCreator - no admin OR no locale - render null");
        return null;
    }

    const _setFirestoreId = (values: sway.IBill) => {
        if (!values.firestoreId) {
            if (!values.externalVersion) {
                return values.externalId;
            }
            return `${values.externalId}v${values.externalVersion}`;
        }
        return values.firestoreId;
    };

    const reduceLegislatorVotes = useCallback(
        (
            externalLegislatorIds: string[],
            support: sway.TLegislatorSupport,
        ): sway.ILegislatorBillSupport => {
            return externalLegislatorIds.reduce(
                (
                    sum: {
                        [externalLegislatorId: string]: sway.TLegislatorSupport;
                    },
                    externalLegislatorId: string,
                ) => {
                    sum[externalLegislatorId] = support;
                    return sum;
                },
                {},
            );
        },
        [],
    );

    const handleSubmit = (
        values: ISubmitValues,
        { setSubmitting }: { setSubmitting: (_isSubmitting: boolean) => void },
    ) => {
        logDev(
            "BillOfTheWeekCreator.handleSubmit - SUBMITTING - new bill of the week - VALUES + SUMMARY REF",
            {
                values,
                summaryRef: summaryRef.current,
            },
        );
        if (!admin) return;

        try {
            values.firestoreId = _setFirestoreId(values);
            values.localeName = state.locale.name;
            values.swaySummary = summaryRef.current;
            values.summaries = {
                sway: summaryRef.current,
            };

            // @ts-ignore
            values.positions = values.organizations.reduce((sum, o) => {
                sum[o.value] = {
                    name: o.value,
                    iconPath: o.iconPath,
                    positions: {
                        [values.firestoreId]: {
                            billFirstoreId: values.firestoreId,
                            support: o.support || false,
                            summary: o.position,
                        },
                    },
                };
                return sum;
            }, {});
            logDev("BillOfTheWeekCreator.handleSubmit - ORGANIZATION POSITIONS -", {
                // @ts-ignore
                positions: values.positions,
            });

            if (!values.swaySummary) {
                notify({
                    level: "warning",
                    title: "Sway summary is required.",
                });
                setSubmitting(false);
                return;
            }

            if (!state.legislators.map((l) => l.externalId).includes(values.sponsorExternalId)) {
                notify({
                    level: "error",
                    title: "Invalid Sponsor",
                    message: "Sponsor is not a valid legislator. Wrong locale?.",
                });
                setSubmitting(false);
                return;
            }

            const concatted = values.supporters.concat(values.opposers).concat(values.abstainers);
            if (concatted.length > state.legislators.length) {
                const dupes = concatted.filter((id: string, index: number) => {
                    return concatted.lastIndexOf(id) !== index;
                });
                notify({
                    level: "error",
                    title: "Duplicate Legislator Positions",
                    message: `Legislators - ${dupes.join(
                        ", ",
                    )} - are duplicated in multiple positions.`,
                });
                logDev(
                    "BillOfTheWeekCreator.handleSubmit - DUPLICATE LEGISLATOR POSITION -",
                    dupes,
                );
                setSubmitting(false);
                return;
            }

            values.legislators = {
                ...reduceLegislatorVotes(values.supporters, Support.For),
                ...reduceLegislatorVotes(values.opposers, Support.Against),
                ...reduceLegislatorVotes(values.abstainers, Support.Abstain),
            };
            if (Object.keys(values.legislators).length !== state.legislators.length) {
                const valueIds = Object.keys(values.legislators);
                const missing = state.legislators.filter((l) => !valueIds.includes(l.externalId));
                notify({
                    level: values.votedate ? "error" : "warning",
                    title: values.votedate
                        ? "Legislators Missing"
                        : "IGNORING Missing Legislators - No Vote Date",
                    message: `Legislators - ${missing
                        .map((l) => l.externalId)
                        .join(", ")} - are missing support.`,
                });
                logDev("BillOfTheWeekCreator.handleSubmit - MISSING LEGISLATOR -", missing);
                setSubmitting(false);
                if (values.votedate) {
                    return;
                }
            }

            logDev("BillOfTheWeekCreator.handleSubmit - VALUES", values);

            setSubmitting(true);
            const setter = httpsCallable(functions, CLOUD_FUNCTIONS.createBillOfTheWeek);
            setter(values)
                .then((response) => {
                    if (
                        (response as HttpsCallableResult<sway.ICloudFunctionResponse>).data.success
                    ) {
                        notify({
                            level: "success",
                            title: "Bill of the Week Created.",
                            message: "created bill of the week",
                        });
                    } else {
                        notify({
                            level: "error",
                            title: "Error",
                            message: "Failed to create bill of the week",
                        });
                    }
                    setSubmitting(false);
                })
                .catch((error: Error) => {
                    logDev(
                        "BillOfTheWeekCreator.handleSubmit - ERROR - setting bill of the week in firebase",
                    );
                    handleError(error);
                    setSubmitting(false);
                });
        } catch (e) {
            console.error(e);
            setSubmitting(false);
        }
    };

    const generateValues = (field: sway.IFormField, values: ICreatorValues) => {
        if (field.component === "generatedText" && field.generateFields) {
            return field.generateFields
                .map((fieldname: string) => values[fieldname])
                .join(field.joiner || " ");
        }
        return "";
    };

    const assignPossibleValues = (
        field: sway.IFormField,
        values?: {
            [key: string]: string[];
        },
    ): sway.TOption[] => {
        if (field.name === "sponsorExternalId") {
            return legislatorIds.map((id) => toSelectOption(toFormattedNameFromExternalId(id), id));
        } else if (field.name === "organizations") {
            return state.organizations.map((o) => ({
                label: o.name,
                value: o.name,
                iconPath: o.iconPath,
                support: get(o.positions),
            }));
        } else if (["supporters", "opposers", "abstainers"].includes(field.name)) {
            const selectedSupporterIds = get(values, "supporters") || [];
            const selectedOpposerIds = get(values, "opposers") || [];
            const selectedAbstainerIds = get(values, "abstainers") || [];
            const selected = selectedSupporterIds
                .concat(selectedOpposerIds)
                .concat(selectedAbstainerIds);

            const options = [];
            for (const externalId of legislatorIds) {
                if (!selected.includes(externalId)) {
                    options.push(externalId);
                }
            }
            return options.map((id) => toSelectOption(toFormattedNameFromExternalId(id), id));
        } else {
            return field.possibleValues || [];
        }
    };

    const handleSetLocale = (_fieldName: string, newLocaleName: string) => {
        const newLocale = LOCALES.find((l) => l.name === newLocaleName);
        if (!newLocale) {
            notify({
                level: "error",
                title: "Error Changing Locale",
                message: "Sorry about that. We're looking into it.",
            });
            return;
        }
        setState((draft) => {
            draft.locale = LOCALES[0];
        });
    };

    const initialbill = {
        externalId: selectedPreviousBOTW?.bill?.externalId || "",
        externalVersion: selectedPreviousBOTW?.bill?.externalVersion || "",
        firestoreId: selectedPreviousBOTW?.bill?.firestoreId || "",
        title: selectedPreviousBOTW?.bill?.title || "",
        link: selectedPreviousBOTW?.bill?.link || "",
        sponsorExternalId: selectedPreviousBOTW?.bill?.sponsorExternalId || "",
        chamber: selectedPreviousBOTW?.bill?.chamber || "council",
        level: selectedPreviousBOTW?.bill?.level || ESwayLevel.Local,
        active: selectedPreviousBOTW?.bill?.active || true,
        swaySummary:
            selectedPreviousBOTW?.bill?.swaySummary ||
            selectedPreviousBOTW?.bill?.summaries?.sway ||
            "",
    } as sway.IBill;

    const initialSupporters = [] as string[];
    const initialOpposers = [] as string[];
    const initialAbstainers = [] as string[];

    for (const legislatorExternalId of Object.keys(legislatorVotes)) {
        const support = legislatorVotes[legislatorExternalId];
        if (support === "for") {
            initialSupporters.push(legislatorExternalId);
        } else if (support === "against") {
            initialOpposers.push(legislatorExternalId);
        } else {
            initialAbstainers.push(legislatorExternalId);
        }
    }

    const initialValues = {
        ...initialbill,
        localeName: LOCALES[0].name,
        organizations:
            (
                selectedPreviousBOTW?.organizations ||
                // @ts-ignore
                selectedPreviousBOTW?.bill?.organizations ||
                []
            )
                // @ts-ignore
                .reduce((sum, o) => {
                    const firestoreId = selectedPreviousBOTW?.bill?.firestoreId;
                    return sum.concat({
                        label: o.name,
                        value: o.name,
                        position: get(o, `positions.${firestoreId}.summary`) || "",
                        support: get(o, `positions.${firestoreId}.support`) || false,
                        iconPath: o.iconPath || "",
                    });
                }, [] as TDataOrganizationPositions) || [],
        legislators: legislatorVotes,
        supporters: initialSupporters,
        opposers: initialOpposers,
        abstainers: initialAbstainers,
    };

    const renderFields = (formik: FormikProps<any>) => {
        const { values, touched, errors, setFieldValue, setTouched } = formik;
        if (!isEmptyObject(errors)) {
            logDev("BillOfTheWeekCreator.renderFields - ERRORS", errors);
        }

        logDev("BillOfTheWeekCreator.renderFields - VALUES -", values);

        const handleSetTouched = (fieldname: string) => {
            if (touched[fieldname]) return;
            setTouched({
                ...touched,
                [fieldname]: true,
            });
        };

        const errorMessage = (fieldname: string): string => {
            return touched[fieldname] &&
                get(errors, fieldname) &&
                !get(errors, fieldname).includes("required")
                ? get(errors, fieldname)
                : "";
        };

        const render = [] as React.ReactNode[];
        let i = 0;
        while (i < BILL_INPUTS.length) {
            const fieldGroup = BILL_INPUTS[i];

            const row = [];
            for (const field of fieldGroup) {
                const generatedValue = generateValues(field, values);

                const { component } = field;

                if (["text", "generatedText"].includes(component)) {
                    const value = component === "text" ? values[field.name] : generatedValue;

                    row.push(
                        <div key={field.name} className="col">
                            <SwayText
                                field={{
                                    ...field,
                                    disabled: Boolean(
                                        field.disabled ||
                                            (field.disableOn && field.disableOn(values)),
                                    ),
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
                                        disabled: Boolean(
                                            field.disabled ||
                                                (field.disableOn && field.disableOn(values)),
                                        ),
                                    }}
                                    values={values}
                                    touched={touched}
                                    errors={errors}
                                    setFieldValue={setFieldValue}
                                    handleSetTouched={handleSetTouched}
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
                                        handleSetLocale(fname, fvalue);
                                        setFieldValue(fname, fvalue);
                                    }}
                                    value={toSelectOption(
                                        toFormattedLocaleName(values.localeName),
                                        values.localeName,
                                    )}
                                    helperText={field.helperText}
                                />
                            </div>,
                        );
                    } else {
                        field.possibleValues = assignPossibleValues(field, values);
                        const val = values[field.name];
                        const { name } = field;
                        const value = Array.isArray(val)
                            ? val.map((v) => toSelectOption(v, v))
                            : val
                            ? toSelectOption(val as string, val as string)
                            : toSelectOption(`Select ${field.label.toLowerCase()}...`, "");

                        logDev("SwaySelect.value", { name, val, value });
                        row.push(
                            <Form.Group key={name} className="col" controlId={name}>
                                {field.label && (
                                    <Form.Label>
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
                                        field.disabled ||
                                        (field.disableOn && field.disableOn(values))
                                    }
                                    value={value}
                                    onChange={(changed) => {
                                        if (field.multi) {
                                            setFieldValue(
                                                name,
                                                (changed as MultiValue<sway.TOption>).map(
                                                    (c) => c.value,
                                                ),
                                            );
                                        } else {
                                            setFieldValue(
                                                name,
                                                (changed as SingleValue<sway.TOption>)?.value,
                                            );
                                        }
                                    }}
                                    closeMenuOnSelect={
                                        !["supporters", "opposers", "abstainers"].includes(name)
                                    }
                                />
                            </Form.Group>,
                        );
                    }
                } else if (field.name === "swaySummary") {
                    row.push(
                        <div key={field.name} className="col">
                            <Form.Label>
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <BillCreatorSummary
                                ref={summaryRef}
                                field={{
                                    ...field,
                                    disabled: Boolean(
                                        field.disabled ||
                                            (field.disableOn && field.disableOn(values)),
                                    ),
                                }}
                            />
                        </div>,
                    );
                } else if (field.name === "swaySummaryPreview") {
                    // noop
                } else if (component === "textarea") {
                    row.push(
                        <div key={field.name} className="col">
                            <Form.Label>
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <SwayTextArea
                                field={{
                                    ...field,
                                    disabled: Boolean(
                                        field.disabled ||
                                            (field.disableOn && field.disableOn(values)),
                                    ),
                                }}
                                value={values[field.name]}
                                error={errorMessage(field.name)}
                                setFieldValue={setFieldValue}
                                handleSetTouched={handleSetTouched}
                                helperText={field.helperText}
                                rows={field.rows}
                            />
                        </div>,
                    );
                } else if (component === "date") {
                    row.push(
                        <div key={field.name} className="col">
                            <Form.Label>
                                {field.label}
                                {field.isRequired ? " *" : " (Optional)"}
                            </Form.Label>
                            <DatePicker
                                className="form-control"
                                placeholderText={"Select date..."}
                                disabled={
                                    field.disabled || (field.disableOn && field.disableOn(values))
                                }
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
                                selected={values[field.name]}
                                onChange={(changed: Date) => {
                                    setFieldValue(field.name, changed);
                                }}
                            />
                            {field.helperText && (
                                <div className="text-muted">{field.helperText}</div>
                            )}
                            <div className="text-danger">{errorMessage(field.name)}</div>
                        </div>,
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

    return (
        <div className="col">
            {state.isLoading && <FullScreenLoading message="Loading..." />}
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
                                <div className="container p-3">
                                    <Form.Group>
                                        <Form.Label id="creator-previous-bills-select">
                                            Previous Bill of the Day
                                        </Form.Label>
                                        <Form.Control
                                            as="select"
                                            className="w-100"
                                            value={state.selectedPreviousBOTWId}
                                            onChange={(event) => {
                                                setState((draft) => {
                                                    draft.selectedPreviousBOTWId =
                                                        event?.target?.value || "new-botw";
                                                });
                                            }}
                                        >
                                            {previousBOTWOptions}
                                        </Form.Control>
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
                                </div>
                            </FormikForm>
                            <BillOfTheWeekCreatorPreview
                                user={user}
                                bill={
                                    {
                                        ...formik.values,
                                        swaySummary: summaryRef.current,
                                    } as sway.IBill
                                }
                                organizations={formik.values.organizations}
                                locale={state.locale}
                            />
                        </>
                    );
                }}
            </Formik>
        </div>
    );
};

export default BillOfTheWeekCreator;
