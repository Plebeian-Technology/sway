/** @format */

import {
    Button,
    CircularProgress,
    createStyles,
    makeStyles,
    Theme,
} from "@material-ui/core";
import { Save } from "@material-ui/icons";
import {
    AREA_CODES_REGEX,
    CLOUD_FUNCTIONS,
    COUNTRY_NAMES,
    STATE_NAMES,
    STATE_CODES_NAMES,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import {
    isEmptyObject,
    toLocale,
    IS_DEVELOPMENT,
    LOCALES_WITHOUT_CONGRESS,
    fromLocaleNameItem,
    titleize,
    findLocale,
    toLocaleName,
} from "@sway/utils";
import firebase from "firebase/app";
import { Form, Formik } from "formik";
import React, { useState } from "react";
import { fire, sway } from "sway";
import * as Yup from "yup";
import {
    FieldValue,
    firestore,
    firestoreConstructor,
    functions as swayFunctions,
} from "../../firebase";
import { useInviteUid, useUser } from "../../hooks";
import { handleError, notify, SWAY_COLORS } from "../../utils";
import Dialog404 from "../dialogs/Dialog404";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SwayText from "../forms/SwayText";
import AddressValidationDialog from "./AddressValidationDialog";
import LocaleSelector from "./LocaleSelector";

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        submitButtonContainer: {
            margin: theme.spacing(2),
            textAlign: "center",
        },
        textContainer: {
            display: "flex",
            flexDirection: "column",
            textAlign: "center",
            margin: theme.spacing(1),
            padding: theme.spacing(1),
        },
        centeredTextContainer: {
            textAlign: "center",
            marginTop: 0,
        },
        typography: {
            margin: theme.spacing(1),
        },
        errorSpan: {
            position: "absolute",
            bottom: 2,
            color: SWAY_COLORS.danger,
        },
        link: {
            fontWeight: "bold",
        },
    }),
);

const RegistrationFields: sway.IFormField[] = [
    {
        name: "localeName",
        component: "select",
        type: "text",
        label: "Locale",
        isRequired: true,
    },
    {
        name: "name",
        component: "text",
        type: "text",
        label: "Name (ex. Abraham Lincoln)",
        isRequired: true,
        autoComplete: "name",
    },
    {
        name: "phone",
        component: "text",
        type: "tel",
        label: "Phone (ex. 1238675309)",
        isRequired: true,
        autoComplete: "tel",
    },
    {
        name: "address1",
        component: "text",
        type: "text",
        label: "Street Address (ex. 1 W Elm St)",
        isRequired: true,
        autoComplete: "shipping address-line1",
    },
    {
        name: "address2",
        component: "text",
        type: "text",
        label: "Street 2 (ex. Apt 1A)",
        isRequired: false,
        autoComplete: "shipping address-line2",
    },
    {
        name: "postalCode",
        component: "text",
        type: "number",
        label: "Zip Code",
        isRequired: true,
        autoComplete: "shipping postal-code",
    },
];

const VALIDATION_SCHEMA = Yup.object().shape({
    name: Yup.string().required(),
    address1: Yup.string().required(),
    address2: Yup.string(),
    city: Yup.string().required(),
    region: Yup.string().required().oneOf(STATE_NAMES),
    regionCode: Yup.string().required().oneOf(Object.keys(STATE_CODES_NAMES)),
    country: Yup.string().required().oneOf(COUNTRY_NAMES),
    postalCode: Yup.string().required().length(5),
    postalCodeExtension: Yup.string().length(4),
    phone: Yup.string().required().length(10).matches(AREA_CODES_REGEX),
});

interface IValidateResponseData {
    address1: string;
    address2: string;
    region: string;
    city: string;
    postalCode: string;
    postalCodeExtension: string;
}

interface IAddressValidation {
    localeName: string;
    original: Partial<sway.IUser>;
    validated?: Partial<sway.IUser>;
}

const Registration: React.FC = () => {
    const classes = useStyles();
    const inviteUid = useInviteUid();
    const [locale, setLocale] = useState<sway.ILocale>(
        LOCALES_WITHOUT_CONGRESS[0],
    );
    const [isLoading, setLoading] = useState<boolean>(false);
    const [addressValidationData, setAddressValidationData] = useState<
        IAddressValidation | undefined
    >();
    const user: sway.IUser | undefined = useUser();

    if (!locale?.name) {
        return <FullScreenLoading message={"Loading Sway Registration..."} />;
    }

    const fireClient = new SwayFireClient(
        firestore,
        toLocale(locale.name),
        firestoreConstructor,
    );

    if (!user?.uid || user.isRegistrationComplete) return <Dialog404 />;

    const defaultUserLocales = () => {
        if (isEmptyObject(user.locales)) {
            if (user.city && user.region && user.country) {
                const localeName = toLocaleName(
                    user.city,
                    user.region,
                    user.country,
                );
                const loc = findLocale(localeName);
                if (!loc) return [];
                return [loc] as sway.IUserLocale[];
            }
            return [];
        }
        return user.locales;
    };

    const initialValues: sway.IUser = {
        createdAt: user.createdAt || FieldValue.serverTimestamp(),
        updatedAt: user.updatedAt || FieldValue.serverTimestamp(),
        email: user.email || "", // from firebase
        uid: user.uid || "", // from firebase
        isRegistrationComplete: user.isRegistrationComplete || false,
        locales: defaultUserLocales(),
        name: user.name || "",
        address1: user.address1 || "",
        address2: user.address2 || "",
        city: user.city ? titleize(user.city) : titleize(locale.city),
        region: user.region ? titleize(user.region) : titleize(locale.region),
        regionCode: user.regionCode || locale.regionCode.toUpperCase(),
        country: user.country || fromLocaleNameItem(locale.country),
        postalCode: user.postalCode || "",
        postalCodeExtension: user.postalCodeExtension || "",
        phone: user.phone || "",
        creationTime: user.creationTime || "",
        lastSignInTime: user.lastSignInTime || "",
        isSwayConfirmed: false,
        isRegisteredToVote: false,
    };

    const handleSubmit = async (values: sway.IUser) => {
        IS_DEVELOPMENT &&
            console.log(
                "(dev) Registration - submitting values to usps validation:",
                values,
            );
        setLoading(true);
        notify({
            level: "info",
            title: "Validating Address",
            message: "Checking your address with USPS",
            duration: 10000,
        });

        const setter = swayFunctions.httpsCallable(
            CLOUD_FUNCTIONS.validateMailingAddress,
        );
        setter(values)
            .then((response: firebase.functions.HttpsCallableResult) => {
                const data: sway.ICloudFunctionResponse = response.data;
                if (data.success) {
                    setAddressValidationData({
                        localeName: locale.name,
                        original: values,
                        validated: data.data as IValidateResponseData,
                    });
                } else {
                    if (IS_DEVELOPMENT) {
                        console.log("address validation empty response data");
                        console.log({ response });
                    }
                    setAddressValidationData({
                        localeName: locale.name,
                        original: values,
                    });
                }
            })
            .catch((error: Error) => {
                if (IS_DEVELOPMENT) {
                    console.log("error validating user address");
                    console.error(error);
                }
                setAddressValidationData({
                    localeName: locale.name,
                    original: values,
                });
            });
    };

    const validateAddress = async ({
        original,
        validated,
    }: {
        original: Partial<sway.IUser>;
        validated?: Partial<sway.IUser> | undefined;
    }) => {
        if (!fireClient) {
            setLoading(false);
            console.error(
                "SwayFire client is undefined in Registration.validateAddress. Skipping user update.",
            );
            return notify({
                level: "error",
                title: "Error",
                message:
                    "We had an issue, try refreshing the page and trying again.",
            });
        }

        const _values = validated ? { ...original, ...validated } : original;
        const values = {
            ..._values,
            invitedBy: isEmptyObject(inviteUid) ? "" : inviteUid,
            region: locale.region,
            regionCode: locale.regionCode,
        } as sway.IUser;

        IS_DEVELOPMENT &&
            console.log(
                "(dev) Registration - submitting values to create new user:",
                values,
            );
        // NOTE: Also creates user settings from DEFAULT_USER_SETTINGS
        const isUpdating = Boolean(
            user && user.uid && user.isRegistrationComplete === false,
        );
        const created = await fireClient
            .users(values.uid)
            .create(values, isUpdating);

        IS_DEVELOPMENT && console.log("(dev) Creating user invites object.");
        await fireClient.userInvites(values.uid).upsert({}).catch(handleError);

        if (created) {
            notify({
                level: "info",
                title: "Registration Received",
                message:
                    "Finding your legislative district. This may take some time.",
                duration: 0,
            });
            fireClient
                .users(created.uid)
                .listen(
                    async (
                        snapshot: fire.TypedDocumentSnapshot<sway.IUser>,
                    ) => {
                        try {
                            const data: sway.IUser | void = snapshot.data();

                            if (!data)
                                throw new Error("Error setting user district.");
                            if (data.isRegistrationComplete) {
                                setLoading(false);
                                window.location.href = "/legislators";
                            }
                        } catch (error) {
                            handleError(
                                error,
                                "Failed to register with Sway. Please try again.",
                            );
                            setLoading(false);
                        }
                    },
                );
        } else {
            handleError(
                new Error("Error registering user."),
                "Failed to register with Sway. Invalid information.",
            );
            setLoading(false);
        }
    };

    return (
        <div className={"registration-container"}>
            <Formik
                initialValues={initialValues}
                onSubmit={handleSubmit}
                validationSchema={VALIDATION_SCHEMA}
                enableReinitialize={true}
            >
                {({ values, touched, errors, setFieldValue, setTouched }) => {
                    const handleSetTouched = (fieldname: string) => {
                        if (touched[fieldname]) return;
                        setTouched({
                            ...touched,
                            [fieldname]: true,
                        });
                    };

                    const errorMessage = (fieldname: string): string => {
                        return (
                            touched[fieldname] &&
                            errors[fieldname] &&
                            !errors[fieldname].includes("required")
                        );
                    };

                    if (IS_DEVELOPMENT && !isEmptyObject(errors)) {
                        console.log(
                            "(dev) Registration formik errors -",
                            errors,
                            values,
                        );
                    }

                    return (
                        <Form>
                            <div
                                style={{ textAlign: "center", marginBottom: 2 }}
                            >
                                {isLoading && !addressValidationData && (
                                    <CircularProgress />
                                )}
                            </div>
                            <div className={"registration-fields-container"}>
                                {RegistrationFields.map(
                                    (field: sway.IFormField) => {
                                        const currentUserFieldValue =
                                            user[field.name];

                                        if (
                                            !currentUserFieldValue &&
                                            field.component === "text"
                                        ) {
                                            return (
                                                <SwayText
                                                    key={field.name}
                                                    field={field}
                                                    value={values[field.name]}
                                                    autoComplete={
                                                        field.autoComplete
                                                    }
                                                    error={errorMessage(
                                                        field.name,
                                                    )}
                                                    setFieldValue={
                                                        setFieldValue
                                                    }
                                                    handleSetTouched={
                                                        handleSetTouched
                                                    }
                                                />
                                            );
                                        }
                                        if (
                                            isEmptyObject(
                                                initialValues.locales,
                                            ) &&
                                            field.name === "localeName"
                                        ) {
                                            return (
                                                <LocaleSelector
                                                    key={field.name}
                                                    locale={locale}
                                                    locales={
                                                        LOCALES_WITHOUT_CONGRESS
                                                    }
                                                    setLocale={setLocale}
                                                />
                                            );
                                        }
                                        return null;
                                    },
                                ).filter(Boolean)}
                            </div>
                            <div className={classes.submitButtonContainer}>
                                <Button
                                    disabled={isLoading}
                                    variant="contained"
                                    color="primary"
                                    size="large"
                                    style={{ color: SWAY_COLORS.white }}
                                    startIcon={<Save />}
                                    type="submit"
                                >
                                    Save
                                </Button>
                            </div>
                        </Form>
                    );
                }}
            </Formik>
            {addressValidationData && (
                <AddressValidationDialog
                    isLoading={isLoading}
                    original={addressValidationData.original}
                    validated={addressValidationData.validated}
                    confirm={validateAddress}
                    cancel={() => {
                        setAddressValidationData(undefined);
                        setLoading(false);
                    }}
                />
            )}
        </div>
    );
};

export default Registration;
