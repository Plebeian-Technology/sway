/** @format */
import { Save } from "@mui/icons-material";
import { Button, Paper } from "@mui/material";
import {
    CLOUD_FUNCTIONS,
    CONGRESS_LOCALE_NAME,
    ESwayLevel,
    LOCALES,
    Support,
} from "@sway/constants";
import { get, isEmptyObject, logDev, toFormattedLocaleName } from "@sway/utils";
import { Form, Formik, FormikProps } from "formik";
import { useEffect, useRef, useState } from "react";
import { sway } from "sway";
import * as Yup from "yup";
import { functions } from "../../firebase";
import { useAdmin } from "../../hooks";
import { notify, swayFireClient } from "../../utils";
import BillCreatorSummary from "../bill/BillCreatorSummary";
import { BILL_INPUTS } from "../bill/creator/inputs";
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
    legislators: { [externalId: string]: string };
}
interface IState {
    legislators: sway.ILegislator[];
    organizations: string[];
}

const BillOfTheWeekCreator: React.FC = () => {
    const summaryRef = useRef<string>("");
    const admin = useAdmin();
    const [locale, setLocale] = useState<sway.ILocale>(LOCALES[0]);
    const [state, setState] = useState<IState>({
        legislators: [],
        organizations: [],
    });

    const { legislators, organizations } = state;
    const legislatorIds = legislators.map(
        (l: sway.ILegislator) => l.externalId,
    );

    useEffect(() => {
        if (!locale) {
            setLocale(LOCALES[0]);
            return;
        }
        const getOrganizations = async () => {
            const orgs = await swayFireClient(locale).organizations().list();
            if (!orgs) return [];
            return orgs.map((o: sway.IOrganization) => o.name);
        };

        const getLegislators = async () => {
            const _legislators: (sway.ILegislator | undefined)[] =
                (await swayFireClient(locale)
                    .legislators()
                    .list()) as sway.ILegislator[];
            return _legislators.filter(Boolean) as sway.ILegislator[];
        };
        admin &&
            Promise.all([getOrganizations(), getLegislators()])
                .then(([orgs, legs]) => {
                    setState((previousState: IState) => ({
                        ...previousState,
                        organizations: orgs,
                        legislators: legs,
                    }));
                })
                .catch(console.error);
    }, [admin, locale, LOCALES]);

    if (!admin || !locale) return null;

    const _setFirestoreId = (values: sway.IBill) => {
        if (!values.firestoreId) {
            if (!values.externalVersion) {
                return values.externalId;
            }
            return `${values.externalId}v${values.externalVersion}`;
        }
        return values.firestoreId;
    };

    const reduce = (
        ids: string[],
        support: "for" | "against" | "abstain",
    ): { [id: string]: "for" | "against" | "abstain" } => {
        return ids.reduce(
            (
                sum: { [id: string]: "for" | "against" | "abstain" },
                id: string,
            ) => {
                sum[id] = support;
                return sum;
            },
            {},
        );
    };

    const handleSubmit = (
        values: ISubmitValues,
        { setSubmitting }: { setSubmitting: (_isSubmitting: boolean) => void },
    ) => {
        logDev("submitting new bill of the week");
        if (!admin) return;

        values.firestoreId = _setFirestoreId(values);
        values.localeName = locale.name;
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
            ...reduce(values.supporters, Support.For),
            ...reduce(values.opposers, Support.Against),
            ...reduce(values.abstainers, Support.Abstain),
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
                console.error(error);
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
        setLocale(newLocale);
    };

    const initialbill = {
        externalId: "",
        externalVersion: "",
        firestoreId: "",
        title: "",
        link: "",
        sponsorExternalId: "",
        chamber: "council",
        level: ESwayLevel.Local,
        active: true,
    } as sway.IBill;

    const initialValues = {
        ...initialbill,
        localeName: CONGRESS_LOCALE_NAME,
        positions: {},
        legislators: {},
        supporters: [],
        opposers: [],
        abstainers: [],
    };

    const renderFields = (formik: FormikProps<any>) => {
        const { values, touched, errors, setFieldValue, setTouched } = formik;
        if (!isEmptyObject(errors)) {
            logDev("ERRORS", errors);
        }

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
                                value={locale.name}
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
    };

    return (
        <Formik
            initialValues={initialValues}
            validationSchema={VALIDATION_SCHEMA}
            onSubmit={handleSubmit}
            enableReinitialize={true}
        >
            {(formik) => {
                return (
                    <Form>
                        <Paper elevation={3} className="col w-100 p-3 m-3">
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
    );
};

export default BillOfTheWeekCreator;
