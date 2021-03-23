/** @format */

import { Button, createStyles, makeStyles, Theme } from "@material-ui/core";
import { CatchingPokemon } from "@material-ui/icons";
import {
    AREA_CODES_REGEX,
    BALTIMORE_COUNTY_LOCALE_NAME,
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
    fromLocaleNameItem,
    getStorage,
    isEmptyObject,
    LOCALE_NOT_LISTED_LABEL,
    logDev,
    removeStorage,
    SELECT_LOCALE_LABEL,
    setStorage,
    titleize,
    toFormattedLocaleName,
    toLocaleName,
} from "@sway/utils";
import firebase from "firebase/app";
import { Form, Formik, FormikProps, FormikValues } from "formik";
import React, { useCallback, useState } from "react";
import { fire, sway } from "sway";
import * as Yup from "yup";
import { functions as swayFunctions } from "../../firebase";
import { useInviteUid, useUser } from "../../hooks";
import { handleError, notify, swayFireClient, SWAY_COLORS } from "../../utils";
import CenteredLoading from "../dialogs/CenteredLoading";
import Dialog404 from "../dialogs/Dialog404";
import AddressValidationDialog from "./AddressValidationDialog";
import RegistrationFields from "./RegistrationFields";

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        submitButtonContainer: {
            margin: theme.spacing(2),
            textAlign: "center",
        },
        submitButton: { color: SWAY_COLORS.white },
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
        formHeader: { textAlign: "center", marginBottom: 2 },
    }),
);

const LOCALE_FIELDS = ["city", "regionCode", "region", "country"];
export const ADDRESS_FIELDS = ["address1", "address2", "postalCode"];
const LOCALE_ADDRESS_FIELDS = LOCALE_FIELDS.concat(ADDRESS_FIELDS);

const REGISTRATION_FIELDS: sway.IFormField[] = [
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
        subLabel:
            "We'll send you a reminder to vote once per week. To opt-out go to 'Settings' after completing registration here.",
    },
    {
        name: "selectedLocale",
        component: "select",
        type: "text",
        label: "Location",
        isRequired: true,
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

    const initialValues: sway.IUser & { selectedLocale?: sway.ILocale } = {
        createdAt: user.createdAt, // set in fire_users
        updatedAt: user.updatedAt, // set in fire_users
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
        selectedLocale: undefined,
    };

    const handleSubmit = async (
        values: sway.IUser & { selectedLocale?: sway.ILocale },
    ) => {
        const { selectedLocale } = values;
        if (!selectedLocale || selectedLocale.name === SELECT_LOCALE_LABEL) {
            logDev(
                "Submitted registration without locale selected. Received -",
                selectedLocale,
            );
            notify({
                level: "error",
                title: "Please select a Locale",
            });
        }

        logDev("Registration - submitting values to usps validation:", values);
        setLoading(true);
        notify({
            level: "info",
            title: "Checking your address with USPS",
        });

        const localeName =
            (selectedLocale as sway.ILocale).name === LOCALE_NOT_LISTED_LABEL
                ? CONGRESS_LOCALE_NAME
                : (selectedLocale as sway.ILocale).name;

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

    const onAddressValidatedByUSPS = async ({
        original,
        validated,
        localeName,
    }: {
        original: Partial<sway.IUser>;
        validated?: Partial<sway.IUser> | undefined;
        localeName: string;
    }) => {
        logDev("Address Validated, Original vs. USPS Validated -", {
            original,
            validated,
            localeName,
        });
        if (!validated) {
            handleError(
                new Error(
                    `No validated data from USPS. Skipping user registration submit. ${JSON.stringify(
                        { original, validated, localeName },
                        null,
                        4,
                    )}`,
                ),
                "Didn't receive validated data from USPS.",
            );
            return;
        }

        const { city } = validated;
        const { region, regionCode, country } = original;
        if (!city || !region || !regionCode || !country) return;

        // const localeName = toLocaleName(city, region, country);
        const locale = findLocale(localeName) || CONGRESS_LOCALE;
        const fireClient = swayFireClient(locale);

        if (locale.name === CONGRESS_LOCALE_NAME) {
            notifyLocaleNotAvailable(locale);
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
            locales: [locale] as sway.IUserLocale[],
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
            handleUserCreatedListenForLegislators(fireClient, created);
        } else {
            handleError(
                new Error("Error registering user."),
                "Failed to register with Sway. Invalid information.",
            );
            setLoading(false);
        }
    };

    const notifyLocaleNotAvailable = (locale: sway.ILocale) => {
        const formatted = toFormattedLocaleName(locale.name);
        const formattedCity = fromLocaleNameItem(locale.city);

        setLoadingMessage(
            `We have no data for ${formatted} but you can still use Sway with your Congressional representatives.\nWe'll update your account once data for ${formattedCity} is added.`,
        );
    };

    const handleUserCreatedListenForLegislators = (
        fireClient: SwayFireClient,
        created: sway.IUser,
    ) => {
        notify({
            level: "info",
            title: "Finding your legislative district.",
            message: "This may take some time.",
        });
        fireClient
            .users(created.uid)
            .listen(
                async (snapshot: fire.TypedDocumentSnapshot<sway.IUser>) => {
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
                            if (user.isEmailVerified || data.isEmailVerified) {
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
    };

    const isLocaleNotListed = useCallback((selectedLocale: sway.ILocale) => {
        return (
            selectedLocale && selectedLocale?.name === LOCALE_NOT_LISTED_LABEL
        );
    }, []);

    const isLocaleField = useCallback((field: sway.IFormField) => {
        return LOCALE_ADDRESS_FIELDS.includes(field.name);
    }, []);

    const isLocaleSelected = useCallback((selectedLocale: sway.ILocale) => {
        return selectedLocale && selectedLocale?.name !== SELECT_LOCALE_LABEL;
    }, []);

    const isLocaleASuperLocale = useCallback((selectedLocale: sway.ILocale) => {
        return (
            selectedLocale &&
            [BALTIMORE_COUNTY_LOCALE_NAME].includes(selectedLocale.name)
        );
    }, []);

    const isAutofillLocaleField = useCallback(
        (field: sway.IFormField, selectedLocale: sway.ILocale) => {
            return (
                LOCALE_FIELDS.includes(field.name) &&
                !isLocaleNotListed(selectedLocale)
            );
        },
        [],
    );

    const isTextField = useCallback(
        (field: sway.IFormField) => field.component === "text",
        [],
    );

    logDev("Registration - render Formik");
    return (
        <div className={"registration-container"}>
            <Formik
                initialValues={initialValues}
                onSubmit={handleSubmit}
                validationSchema={VALIDATION_SCHEMA}
                enableReinitialize={true}
            >
                {(formik: FormikProps<FormikValues>) => {
                    return (
                        <Form>
                            <div className={classes.formHeader}>
                                {isLoading && !addressValidationData && (
                                    <CenteredLoading message={loadingMessage} />
                                )}
                            </div>
                            <RegistrationFields
                                user={user}
                                fields={REGISTRATION_FIELDS}
                                formik={formik}
                                isLocaleField={isLocaleField}
                                isLocaleSelected={isLocaleSelected}
                                isLocaleASuperLocale={isLocaleASuperLocale}
                                isAutofillLocaleField={isAutofillLocaleField}
                                isTextField={isTextField}
                            />
                            <div className={classes.submitButtonContainer}>
                                <Button
                                    disabled={isLoading}
                                    variant="contained"
                                    color="primary"
                                    size="large"
                                    className={classes.submitButton}
                                    startIcon={<CatchingPokemon />}
                                    endIcon={<CatchingPokemon />}
                                    type="submit"
                                >
                                    Find Representatives
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
                    localeName={addressValidationData.localeName}
                    confirm={onAddressValidatedByUSPS}
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
