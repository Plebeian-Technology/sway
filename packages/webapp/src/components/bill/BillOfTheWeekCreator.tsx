/** @format */

import {
    Button,
    createStyles,
    makeStyles,
    Paper,
    Theme,
} from "@material-ui/core";
import { Save } from "@material-ui/icons";
import {
    CLOUD_FUNCTIONS,
    DEFAULT_LOCALE_NAME,
    ESwayLevel,
    LOCALES,
    Support,
} from "@sway/constants";
import { Form, Formik } from "formik";
import { useEffect, useState } from "react";
import { sway } from "sway";
import * as Yup from "yup";
import { functions } from "../../firebase";
import { useAdmin } from "../../hooks";
import { legisFire, notify, swayBlackRGBA } from "../../utils";
import { IS_DEVELOPMENT, toFormattedLocaleName } from "@sway/utils"
import SwayAutoSelect from "../forms/SwayAutoSelect";
import SwaySelect from "../forms/SwaySelect";
import SwayText from "../forms/SwayText";
import SwayTextArea from "../forms/SwayTextArea";
import "./billcreator.css";
import BillCreatorOrganizations from "./BillCreatorOrganizations";

const BILL_INPUTS: sway.IFormField[] = [
    {
        name: "externalId",
        component: "text",
        type: "text",
        label: "Bill External Id",
        isRequired: true,
    },
    {
        name: "externalVersion",
        component: "text",
        type: "text",
        label: "Bill External Version",
        isRequired: false,
        default: "",
    },
    {
        name: "firestoreId",
        component: "generatedText",
        type: "text",
        generateFields: ["externalId", "externalVersion"],
        joiner: "v",
        label: "Generated Firestore ID",
        isRequired: true,
        disabled: true,
    },
    {
        name: "title",
        component: "text",
        type: "text",
        label: "Bill Title",
        isRequired: true,
    },
    {
        name: "link",
        component: "text",
        type: "text",
        label: "Bill Link",
        isRequired: true,
    },
    {
        name: "sponsorExternalId",
        component: "select",
        type: "text",
        label: "Legislator Sponsor External Id",
        isRequired: true,
    },
    {
        name: "localeName",
        component: "select",
        type: "text",
        label: "Locale Name",
        isRequired: true,
    },
    {
        name: "chamber",
        component: "text",
        type: "text",
        label: "Chamber",
        isRequired: true,
        default: "council",
        disabled: true,
    },
    {
        name: "relatedBillIds",
        component: "textarea",
        type: "text",
        label: "Related Bill IDs",
        isRequired: false,
    },
    {
        name: "swaySummary",
        component: "textarea",
        type: "text",
        label: "Sway Bill Summary",
        isRequired: true,
    },
    {
        name: "organizations",
        component: "select",
        type: "text",
        label: "Organizations",
        isRequired: false,
    },
    {
        name: "supporters",
        component: "select",
        type: "text",
        label: "Supporters",
        isRequired: false,
        multi: true,
    },
    {
        name: "opposers",
        component: "select",
        type: "text",
        label: "Opposers",
        isRequired: false,
        multi: true,
    },
    {
        name: "abstainers",
        component: "select",
        type: "text",
        label: "Abstainers",
        isRequired: false,
        multi: true,
    },
];

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        container: {
            padding: 20,
            backgroundColor: swayBlackRGBA("0.6"),
        },
        form: {
            width: "100%",
        },
        fieldsContainer: {
            display: "flex",
            flexDirection: "row",
            flexWrap: "wrap",
            alignItems: "center",
            justifyContent: "center",
            width: "100%",
            margin: `${theme.spacing(3)}px auto`,
        },
        field: {
            width: "70%",
            margin: "10px auto",
            padding: 10,
        },
        buttonContainer: {
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
        },
        text: {},
        input: {
            "&:focus": {
                width: "100%",
            },
        },
        textareaContainer: { display: "flex", flexDirection: "column" },
        textarea: { padding: 10 },
        submitButtonContainer: {
            textAlign: "center",
        },
        submitButton: {
            margin: `${theme.spacing(3)} auto`,
        },
        orgsContainer: {
            width: "100%",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
        },
    }),
);

const VALIDATION_SCHEMA = Yup.object().shape({
    externalId: Yup.string().required(),
    externalVersion: Yup.string(),
    // firestoreId: Yup.string().required(),
    title: Yup.string().required(),
    link: Yup.string().required().url(),
    swaySummary: Yup.string().required(),
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
    const classes = useStyles();
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
            const orgs = await legisFire(locale).organizations().list();
            if (!orgs) return [];
            return orgs.map((o: sway.IOrganization) => o.name);
        };

        const getLegislators = async () => {
            const _legislators: (
                | sway.ILegislator
                | undefined
            )[] = (await legisFire(locale)
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
        console.log("submitting new bill of the week");
        if (!admin) return;
        values.firestoreId = _setFirestoreId(values);
        values.localeName = locale.name;

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
            console.log("DUPES -", dupes);
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
            console.log("MISSING -", missing);
            setSubmitting(false);
            return;
        }

        if (IS_DEVELOPMENT) {
            console.log("submitting values", values);
        }

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
                if (IS_DEVELOPMENT) {
                    console.log("error setting bill of the week in firebase");
                    console.error(error);
                }
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
        localeName: DEFAULT_LOCALE_NAME,
        positions: {},
        legislators: {},
        supporters: [],
        opposers: [],
        abstainers: [],
    };

    return (
        <Formik
            initialValues={initialValues}
            validationSchema={VALIDATION_SCHEMA}
            onSubmit={handleSubmit}
            enableReinitialize={true}
        >
            {({
                values,
                touched,
                errors,
                setFieldValue,
                setTouched,
                isSubmitting,
            }) => {
                const handleSetTouched = (fieldname: string) => {
                    if (touched[fieldname]) return;
                    setTouched({
                        ...touched,
                        [fieldname]: true,
                    });
                };

                const errorMessage = (fieldname: string) => {
                    return (
                        touched[fieldname] &&
                        errors[fieldname] &&
                        !errors[fieldname].includes("required")
                    );
                };

                return (
                    <Form>
                        <Paper elevation={3} className={classes.container}>
                            <div className={classes.fieldsContainer}>
                                {BILL_INPUTS.map((field: sway.IFormField) => {
                                    const generatedValue = generateValues(
                                        field,
                                        values,
                                    );

                                    if (field.name === "localeName") {
                                        field.possibleValues = assignPossibleValues(
                                            field,
                                        );
                                        return (
                                            <SwaySelect
                                                key={field.name}
                                                field={field}
                                                error={""}
                                                handleSetTouched={() => null}
                                                setFieldValue={handleSetLocale}
                                                value={locale.name}
                                            />
                                        );
                                    }

                                    if (
                                        field.component === "text" ||
                                        field.component === "generatedText"
                                    ) {
                                        const value =
                                            field.component === "text"
                                                ? values[field.name]
                                                : generatedValue;

                                        return (
                                            <SwayText
                                                key={field.name}
                                                field={field}
                                                value={value}
                                                error={errorMessage(field.name)}
                                                setFieldValue={setFieldValue}
                                                handleSetTouched={
                                                    handleSetTouched
                                                }
                                            />
                                        );
                                    }

                                    if (field.component === "select") {
                                        field.possibleValues = assignPossibleValues(
                                            field,
                                        );

                                        if (field.name === "organizations") {
                                            return (
                                                <div
                                                    key={field.name}
                                                    className={
                                                        classes.orgsContainer
                                                    }
                                                >
                                                    <BillCreatorOrganizations
                                                        field={field}
                                                        values={values}
                                                        touched={touched}
                                                        errors={errors}
                                                        setFieldValue={
                                                            setFieldValue
                                                        }
                                                        handleSetTouched={
                                                            handleSetTouched
                                                        }
                                                    />
                                                </div>
                                            );
                                        }
                                        return (
                                            <SwayAutoSelect
                                                key={field.name}
                                                multiple={
                                                    field.multi && field.multi
                                                }
                                                field={field}
                                                value={values[field.name]}
                                                error={errorMessage(field.name)}
                                                setFieldValue={setFieldValue}
                                                handleSetTouched={
                                                    handleSetTouched
                                                }
                                            />
                                        );
                                    }

                                    if (field.component === "textarea") {
                                        return (
                                            <SwayTextArea
                                                key={field.name}
                                                field={field}
                                                value={values[field.name]}
                                                error={errorMessage(field.name)}
                                                setFieldValue={setFieldValue}
                                                handleSetTouched={
                                                    handleSetTouched
                                                }
                                            />
                                        );
                                    }

                                    return null;
                                }).filter(Boolean)}
                            </div>
                            <div className={classes.submitButtonContainer}>
                                <Button
                                    className={classes.submitButton}
                                    disabled={isSubmitting}
                                    variant="contained"
                                    color="primary"
                                    size="large"
                                    startIcon={<Save />}
                                    type="submit"
                                >
                                    Save
                                </Button>
                            </div>
                        </Paper>
                    </Form>
                );
            }}
        </Formik>
    );
};

export default BillOfTheWeekCreator;
