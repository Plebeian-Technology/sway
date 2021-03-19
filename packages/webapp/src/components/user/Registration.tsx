/** @format */

import { Button, createStyles, makeStyles, Theme } from "@material-ui/core";
import { Save } from "@material-ui/icons";
import {
    AREA_CODES_REGEX,
    CLOUD_FUNCTIONS,
    CONGRESS_LOCALE,
    CONGRESS_LOCALE_NAME,
    COUNTRY_NAMES,
    STATE_CODES_NAMES,
    STATE_NAMES,
    SWAY_REDEEMING_INVITE_FROM_UID_COOKIE,
    SWAY_USER_REGISTERED,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import {
    findLocale,
    flatten,
    getStorage,
    isEmptyObject,
    IS_DEVELOPMENT,
    logDev,
    removeStorage,
    setStorage,
    titleize,
    toFormattedLocaleName,
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
import CenteredLoading from "../dialogs/CenteredLoading";
import Dialog404 from "../dialogs/Dialog404";
import SwaySelect from "../forms/SwaySelect";
import SwayText from "../forms/SwayText";
import AddressValidationDialog from "./AddressValidationDialog";

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
        autoComplete: "tel-national",
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
        name: "city",
        component: "text",
        type: "text",
        label: "City",
        isRequired: true,
        autoComplete: "shipping address-level2",
    },
    {
        name: "regionCode",
        component: "select",
        type: "text",
        label: "State",
        possibleValues: Object.keys(STATE_CODES_NAMES).sort(),
        isRequired: true,
        autoComplete: "shipping address-level1",
    },
    {
        name: "postalCode",
        component: "text",
        type: "number",
        label: "Zip Code",
        isRequired: true,
        autoComplete: "shipping postal-code",
    },
    {
        name: "country",
        component: "select",
        type: "text",
        label: "Country",
        isRequired: true,
        possibleValues: COUNTRY_NAMES.sort(),
        default: "United States",
        disabled: true,
        autoComplete: "shipping country-name",
    },
];

const VALIDATION_SCHEMA = Yup.object().shape({
    name: Yup.string().required(),
    address1: Yup.string().required(),
    address2: Yup.string(),
    city: Yup.string().required(),
    region: Yup.string().required().oneOf(STATE_NAMES),
    regionCode: Yup.string().required().oneOf(Object.keys(STATE_CODES_NAMES)),
    country: Yup.string()
        .required()
        .oneOf(
            flatten([COUNTRY_NAMES, COUNTRY_NAMES.map((s) => s.toLowerCase())]),
        ),
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
    const invitedByUid = useInviteUid();
    const [isLoading, setLoading] = useState<boolean>(false);
    const [loadingMessage, setLoadingMessage] = useState<string>("");
    const [addressValidationData, setAddressValidationData] = useState<
        IAddressValidation | undefined
    >();
    const user: sway.IUser | undefined = useUser();

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
        city: user.city ? titleize(user.city) : "",
        region: user.region ? titleize(user.region) : "",
        regionCode: user.regionCode || "",
        country: titleize(user.country) || COUNTRY_NAMES[0],
        postalCode: user.postalCode || "",
        postalCodeExtension: user.postalCodeExtension || "",
        phone: user.phone ? user.phone : "",
        creationTime: user.creationTime || "",
        lastSignInTime: user.lastSignInTime || "",
        isSwayConfirmed: false,
        isRegisteredToVote: false,
        isEmailVerified: user.isEmailVerified || false,
    };

    const handleSubmit = async (values: sway.IUser) => {
        logDev("Registration - submitting values to usps validation:", values);
        setLoading(true);
        notify({
            level: "info",
            message: "Checking your address with USPS",
        });

        const localeName = toLocaleName(
            values.city,
            values.region,
            values.country,
        );

        const setter = swayFunctions.httpsCallable(
            CLOUD_FUNCTIONS.validateMailingAddress,
        );
        setter({
            ...values,
            address1: values.address1.includes("#")
                ? values.address1.split("#")[0]
                : values.address1,
        })
            .then((response: firebase.functions.HttpsCallableResult) => {
                const data: sway.ICloudFunctionResponse = response.data;
                if (data.success) {
                    setAddressValidationData({
                        localeName: localeName,
                        original: values,
                        validated: data.data as IValidateResponseData,
                    });
                } else {
                    logDev("address validation empty response data", {
                        response,
                    });
                    setAddressValidationData({
                        localeName: localeName,
                        original: values,
                    });
                }
            })
            .catch((error: Error) => {
                console.error(error);
                logDev("error validating user address");
                setAddressValidationData({
                    localeName: localeName,
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
        logDev("Address Validated, Original vs. USPS Validated -", {
            original,
            validated,
        });

        if (!validated) return;

        const { city } = validated;
        const { region, regionCode, country } = original;
        if (!city || !region || !regionCode || !country) return;

        const localeName = toLocaleName(city, region, country);
        const locale = findLocale(localeName) || CONGRESS_LOCALE;

        if (locale.name === CONGRESS_LOCALE_NAME) {
            setLoadingMessage(
                `We have no data for ${toFormattedLocaleName(
                    localeName,
                )} but you can still use Sway with your Congressional representatives.\nWe'll update your account once data for ${toFormattedLocaleName(
                    localeName.split("-")[0],
                    false,
                )} is added.`,
            );
        }

        const fireClient = new SwayFireClient(
            firestore,
            locale,
            firestoreConstructor,
        );

        if (!fireClient) {
            setLoading(false);
            console.error(
                "SwayFire client is undefined in Registration.validateAddress. Skipping user update.",
            );
            return notify({
                level: "error",
                message:
                    "We had an issue, try refreshing the page and trying again.",
            });
        }

        const _values = validated ? { ...original, ...validated } : original;
        const values = {
            ..._values,
            invitedBy: isEmptyObject(invitedByUid)
                ? getStorage(SWAY_REDEEMING_INVITE_FROM_UID_COOKIE)
                : invitedByUid,
            country: country.toLowerCase(),
            city: city.toLowerCase(),
            region: region.toLowerCase(),
            regionCode: regionCode.toUpperCase(),
            address1: _values?.address1?.includes("#")
                ? _values?.address1?.split("#")[0]
                : _values.address1,
        } as sway.IUser;

        logDev("Registration - submitting values to create new user:", values);
        // NOTE: Also creates user settings from DEFAULT_USER_SETTINGS
        const isUpdating = Boolean(
            user && user.uid && user.isRegistrationComplete === false,
        );
        const created = await fireClient
            .users(values.uid)
            .create(values, isUpdating);

        logDev("Creating user invites object.");
        await fireClient.userInvites(values.uid).upsert({}).catch(handleError);

        if (created) {
            notify({
                level: "info",
                message:
                    "Finding your legislative district. This may take some time.",
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
                                setStorage(SWAY_USER_REGISTERED, "1");
                                removeStorage(
                                    SWAY_REDEEMING_INVITE_FROM_UID_COOKIE,
                                );
                                setLoading(false);
                                if (
                                    user.isEmailVerified ||
                                    data.isEmailVerified
                                ) {
                                    window.location.href = "/legislators";
                                } else {
                                    window.location.href =
                                        "/?needsEmailActivation=1";
                                }
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
                        logDev("Registration formik errors -", errors, values);
                    }

                    const handleSetFieldValue = (
                        field: string,
                        value: string[] | string | null,
                        shouldValidate?: boolean | undefined,
                    ) => {
                        if (
                            typeof value === "string" &&
                            field === "regionCode"
                        ) {
                            setFieldValue(field, value, shouldValidate);
                            setFieldValue(
                                "region",
                                STATE_CODES_NAMES[value],
                                shouldValidate,
                            );
                        } else {
                            setFieldValue(field, value, shouldValidate);
                        }
                    };

                    return (
                        <Form>
                            <div
                                style={{ textAlign: "center", marginBottom: 2 }}
                            >
                                {isLoading && !addressValidationData && (
                                    <CenteredLoading message={loadingMessage} />
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
                                                    error={errorMessage(
                                                        field.name,
                                                    )}
                                                    setFieldValue={
                                                        handleSetFieldValue
                                                    }
                                                    handleSetTouched={
                                                        handleSetTouched
                                                    }
                                                />
                                            );
                                        }

                                        if (
                                            !currentUserFieldValue &&
                                            field.component === "select"
                                        ) {
                                            return (
                                                <SwaySelect
                                                    key={field.name}
                                                    field={field}
                                                    value={values[field.name]}
                                                    error={errorMessage(
                                                        field.name,
                                                    )}
                                                    setFieldValue={
                                                        handleSetFieldValue
                                                    }
                                                    handleSetTouched={
                                                        handleSetTouched
                                                    }
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
                    loadingMessage={loadingMessage}
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
