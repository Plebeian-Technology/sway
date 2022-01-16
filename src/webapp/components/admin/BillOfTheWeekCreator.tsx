/** @format */
import { Save } from "@mui/icons-material";
import {
    Button,
    FormControl,
    InputLabel,
    MenuItem,
    Paper,
    Select,
    SelectChangeEvent,
} from "@mui/material";
import {
    CLOUD_FUNCTIONS,
    CONGRESS_LOCALE_NAME,
    ESwayLevel,
    LOCALES,
    Support,
} from "src/constants";
import { get, isEmptyObject, logDev, toFormattedLocaleName } from "src/utils";
import { Form, Formik, FormikProps } from "formik";
import { useCallback, useEffect, useRef } from "react";
import { sway } from "sway";
import * as Yup from "yup";
import { functions } from "../../firebase";
import { useUserWithSettingsAdmin } from "../../hooks";
import { useBills } from "../../hooks/bills";
import { useImmer } from "../../hooks/useImmer";
import { useLegislatorVotes } from "../../hooks/useLegislatorVotes";
import { handleError, notify, swayFireClient } from "../../utils";
import BillCreatorSummary from "../bill/BillCreatorSummary";
import { BILL_INPUTS } from "../bill/creator/inputs";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SwayAutoSelect from "../forms/SwayAutoSelect";
import SwaySelect from "../forms/SwaySelect";
import SwayText from "../forms/SwayText";
import SwayTextArea from "../forms/SwayTextArea";
import BillCreatorOrganizations from "./BillCreatorOrganizations";

const VALIDATION_SCHEMA = Yup.object().shape({
    externalId: Yup.string().required(),
    externalVersion: Yup.string(),
    title: Yup.string().required(),
    link: Yup.string().required().url(),
    swaySummary: Yup.string(),
    sponsorExternalId: Yup.string().required(),
    localeName: Yup.string().required(),
    positions: Yup.object().notRequired(),
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
}
interface IState {
    isLoading: boolean;
    locale: sway.ILocale;
    selectedPreviousBOTWId: string;
    legislators: sway.ILegislator[];
    organizations: string[];
}

const BillOfTheWeekCreator: React.FC = () => {
    const summaryRef = useRef<string>("");
    const user = useUserWithSettingsAdmin();
    const admin = user.isAdmin;
    const [bills, getBills] = useBills();
    const [legislatorVotes, getLegislatorVotes] = useLegislatorVotes();
    const [state, setState] = useImmer<IState>({
        isLoading: false,
        locale: LOCALES[0],
        selectedPreviousBOTWId: "new-botw",
        legislators: [],
        organizations: [],
    });
    const selectedPreviousBOTW = bills.find(
        (b) => b.bill.firestoreId === state.selectedPreviousBOTWId,
    );
    const previousBOTWOptions = [
        <MenuItem key={"new-botw"} value={"new-botw"}>
            New Bill of the Week
        </MenuItem>,
    ].concat(
        bills.map((b) => (
            <MenuItem
                key={b.bill.firestoreId}
                value={b.bill.firestoreId}
            >{`${b.bill.externalId} - ${b.bill.title}`}</MenuItem>
        )),
    );

    const { legislators, organizations } = state;
    const legislatorIds = legislators.map(
        (l: sway.ILegislator) => l.externalId,
    );

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
        logDev(
            "BillOfTheWeekCreator.useEffect - set summary ref to summary from selected bill",
        );
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
        if (selectedPreviousBOTW?.bill?.firestoreId && legislatorIds) {
            logDev(
                "BillOfTheWeekCreator.useEffect - set legislator votes for selected bill",
            );
            startLoading();
            getLegislatorVotes(
                legislatorIds,
                selectedPreviousBOTW.bill.firestoreId,
            )
                .then(stopLoading)
                .catch((error) => {
                    stopLoading();
                    handleError(error);
                });
        }
    }, [
        state.locale.name,
        state.selectedPreviousBOTWId,
        isEmptyObject(legislatorIds),
    ]);

    useEffect(() => {
        if (!state.locale) {
            setState((draft) => {
                draft.locale = LOCALES[0];
            });
            logDev(
                "BillOfTheWeekCreator.useEffect - set locale to LOCALES.first",
            );
            return;
        }

        startLoading();
        const getOrganizations = async () => {
            const orgs = await swayFireClient(state.locale)
                .organizations()
                .list();
            logDev("BillOfTheWeekCreator.useEffect - get organizations");
            if (!orgs) return [];
            return orgs.map((o: sway.IOrganization) => o.name);
        };

        const getLegislators = async () => {
            logDev("BillOfTheWeekCreator.useEffect - get legislators");
            const _legislators: (sway.ILegislator | undefined)[] =
                (await swayFireClient(state.locale)
                    .legislators()
                    .list()) as sway.ILegislator[];
            return _legislators.filter(Boolean) as sway.ILegislator[];
        };

        admin &&
            Promise.all([getOrganizations(), getLegislators()])
                .then(([orgs, legs]) => {
                    logDev(
                        "BillOfTheWeekCreator.useEffect - set organizations and legislators state",
                    );
                    setState((previousState: IState) => ({
                        ...previousState,
                        isLoading: false,
                        organizations: orgs,
                        legislators: legs,
                    }));
                })
                .catch((error) => {
                    stopLoading();
                    handleError(error);
                });
    }, [admin, state.locale.name, state.selectedPreviousBOTWId]);

    if (!admin || !state.locale) return null;

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
        logDev("submitting new bill of the week");
        if (!admin) return;

        values.firestoreId = _setFirestoreId(values);
        values.localeName = state.locale.name;
        values.swaySummary = summaryRef.current;
        values.summaries = {
            sway: summaryRef.current,
        };

        if (!values.swaySummary) {
            notify({
                level: "warning",
                title: "Sway summary is required.",
            });
            setSubmitting(false);
            return;
        }

        if (
            !legislators
                .map((l) => l.externalId)
                .includes(values.sponsorExternalId)
        ) {
            notify({
                level: "error",
                title: "Invalid Sponsor",
                message: "Sponsor is not a valid legislator. Wrong locale?.",
            });
            setSubmitting(false);
            return;
        }

        const concatted = values.supporters
            .concat(values.opposers)
            .concat(values.abstainers);
        if (concatted.length > legislators.length) {
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
            logDev("DUPES -", dupes);
            setSubmitting(false);
            return;
        }

        values.legislators = {
            ...reduceLegislatorVotes(values.supporters, Support.For),
            ...reduceLegislatorVotes(values.opposers, Support.Against),
            ...reduceLegislatorVotes(values.abstainers, Support.Abstain),
        };
        if (Object.keys(values.legislators).length !== legislators.length) {
            const valueIds = Object.keys(values.legislators);
            const missing = legislators.filter(
                (l) => !valueIds.includes(l.externalId),
            );
            notify({
                level: "error",
                title: "Legislators Missing",
                message: `Legislators - ${missing
                    .map((l) => l.externalId)
                    .join(", ")} - are missing support.`,
            });
            logDev("MISSING -", missing);
            setSubmitting(false);
            return;
        }

        logDev("submitting values", values);

        setSubmitting(true);
        const setter = functions.httpsCallable(
            CLOUD_FUNCTIONS.createBillOfTheWeek,
        );
        setter(values)
            .then((response) => {
                if (response.data.success) {
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
                logDev("error setting bill of the week in firebase");
                handleError(error);
                setSubmitting(false);
            });
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
    ): string[] | { label: string; value: string }[] | undefined => {
        if (field.name === "sponsorExternalId") {
            return legislatorIds;
        }
        if (field.name === "organizations") {
            return organizations;
        }
        if (field.name === "localeName") {
            return LOCALES.map((l) => {
                return {
                    label: toFormattedLocaleName(l.name),
                    value: l.name,
                };
            });
        }
        if (["supporters", "opposers", "abstainers"].includes(field.name)) {
            return legislators.map((l) => l.externalId);
        }
        return [];
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
        localeName: CONGRESS_LOCALE_NAME,
        organizations:
            selectedPreviousBOTW?.organizations?.map((o) => o.name) || [],
        positions:
            selectedPreviousBOTW?.organizations?.reduce((sum, o) => {
                const firestoreId = selectedPreviousBOTW?.bill?.firestoreId;
                if (firestoreId && o.positions[firestoreId]) {
                    sum[o.name] = {
                        ...o.positions[firestoreId],
                        position: o.positions[firestoreId].summary,
                    };
                }
                return sum;
            }, {}) || {},
        legislators: legislatorVotes,
        supporters: initialSupporters,
        opposers: initialOpposers,
        abstainers: initialAbstainers,
    };

    const renderFields = useCallback(
        (formik: FormikProps<any>) => {
            const { values, touched, errors, setFieldValue, setTouched } =
                formik;
            if (!isEmptyObject(errors)) {
                logDev("ERRORS", errors);
            }

            logDev("BillOfTheWeekCreator.renderFields");

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

                    if (field.name === "localeName") {
                        field.possibleValues = assignPossibleValues(field);
                        row.push(
                            <div key={field.name} className="col">
                                <SwaySelect
                                    field={field}
                                    error={""}
                                    handleSetTouched={() => null}
                                    setFieldValue={handleSetLocale}
                                    value={state.locale.name}
                                    helperText={field.helperText}
                                />
                            </div>,
                        );
                    } else if (["text", "generatedText"].includes(component)) {
                        const value =
                            component === "text"
                                ? values[field.name]
                                : generatedValue;

                        row.push(
                            <div key={field.name} className="col">
                                <SwayText
                                    field={field}
                                    value={value}
                                    error={errorMessage(field.name)}
                                    setFieldValue={setFieldValue}
                                    handleSetTouched={handleSetTouched}
                                    helperText={field.helperText}
                                />
                            </div>,
                        );
                    } else if (component === "select") {
                        field.possibleValues = assignPossibleValues(field);

                        if (field.name === "organizations") {
                            row.push(
                                <div key={field.name} className="col-12">
                                    <BillCreatorOrganizations
                                        field={field}
                                        values={values}
                                        touched={touched}
                                        errors={errors}
                                        setFieldValue={setFieldValue}
                                        handleSetTouched={handleSetTouched}
                                    />
                                </div>,
                            );
                        } else {
                            row.push(
                                <div key={field.name} className="col">
                                    <SwayAutoSelect
                                        multiple={field.multi && field.multi}
                                        field={field}
                                        value={values[field.name]}
                                        error={errorMessage(field.name)}
                                        setFieldValue={setFieldValue}
                                        handleSetTouched={handleSetTouched}
                                        helperText={field.helperText}
                                        isKeepOpen={field.multi && field.multi}
                                    />
                                </div>,
                            );
                        }
                    } else if (field.name === "swaySummary") {
                        row.push(
                            <div key={field.name} className="col">
                                <BillCreatorSummary
                                    ref={summaryRef}
                                    field={field}
                                />
                            </div>,
                        );
                    } else if (field.name === "swaySummaryPreview") {
                        // noop
                    } else if (component === "textarea") {
                        row.push(
                            <div key={field.name} className="col">
                                <SwayTextArea
                                    field={field}
                                    value={values[field.name]}
                                    error={errorMessage(field.name)}
                                    setFieldValue={setFieldValue}
                                    handleSetTouched={handleSetTouched}
                                    helperText={field.helperText}
                                    rows={field.rows}
                                />
                            </div>,
                        );
                    }
                }
                render.push(
                    <div key={`row-${render.length}`} className="row my-3">
                        {row}
                    </div>,
                );
                i++;
            }
            return render;
        },
        [state.locale.name, state.selectedPreviousBOTWId],
    );

    return (
        <>
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
                        <Form>
                            <Paper elevation={3} className="container p-3">
                                <FormControl fullWidth>
                                    <InputLabel id="creator-previous-bills-select">
                                        Previous Bill of the Day
                                    </InputLabel>
                                    <Select
                                        className="w-100"
                                        labelId="creator-previous-bills-select"
                                        label="Previous Bill of the Day"
                                        variant="outlined"
                                        value={state.selectedPreviousBOTWId}
                                        onChange={(
                                            event: SelectChangeEvent<string>,
                                        ) => {
                                            setState((draft) => {
                                                draft.selectedPreviousBOTWId =
                                                    event?.target?.value ||
                                                    "new-botw";
                                            });
                                        }}
                                    >
                                        {previousBOTWOptions}
                                    </Select>
                                </FormControl>
                                <hr />
                                {renderFields(formik)}
                                <Button
                                    disabled={formik.isSubmitting}
                                    variant="contained"
                                    color="primary"
                                    size="large"
                                    startIcon={<Save />}
                                    type="submit"
                                >
                                    Save
                                </Button>
                            </Paper>
                        </Form>
                    );
                }}
            </Formik>
        </>
    );
};

export default BillOfTheWeekCreator;
