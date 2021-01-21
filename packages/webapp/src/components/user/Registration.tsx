/** @format */

import {
    Button,
    CircularProgress,
    createStyles,
    makeStyles,
    Theme
} from "@material-ui/core";
import { Save } from "@material-ui/icons";
import {
    AREA_CODES_REGEX,
    CLOUD_FUNCTIONS,
    COUNTRY_NAMES,

    STATE_CODES_NAMES,
    STATE_NAMES
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import firebase from "firebase/app";
import { Form, Formik } from "formik";
import React from "react";
import { fire, sway } from "sway";
import * as Yup from "yup";
import {
    FieldValue,
    firestore,
    firestoreConstructor,
    functions as swayFunctions
} from "../../firebase";
import { useInviteUid, useLocale, useUser } from "../../hooks";
import {
    handleError,
    isEmptyObject,
    IS_DEVELOPMENT,
    notify,
    swayRed,
    swayWhite,
    titleize
} from "../../utils";
import {
    fromLocaleNameItem,
    splitLocaleName,
    toLocale,
    toLocaleName
} from "../../utils/locales";
import Dialog404 from "../dialogs/Dialog404";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SwayText from "../forms/SwayText";
import AddressValidationDialog from "./AddressValidationDialog";
import ReduxLocaleSelector from "./ReduxLocaleSelector";

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
            color: swayRed,
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
    },
    {
        name: "phone",
        component: "text",
        type: "tel",
        label: "Phone (ex. 1238675309)",
        isRequired: true,
    },
    {
        name: "address1",
        component: "text",
        type: "text",
        label: "Street Address (ex. 1 W Elm St)",
        isRequired: true,
    },
    {
        name: "address2",
        component: "text",
        type: "text",
        label: "Street 2 (ex. Apt 1A)",
        isRequired: false,
    },
    {
        name: "postalCode",
        component: "text",
        type: "number",
        label: "Zip Code",
        isRequired: true,
    },
];

const VALIDATION_SCHEMA = Yup.object().shape({
    name: Yup.string().required(),
    address1: Yup.string().required(),
    address2: Yup.string(),
    city: Yup.string().required(),
    region: Yup.string().required().oneOf(STATE_NAMES),
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

const Registration: React.FC = () => {
    const classes = useStyles();
    const inviteUid = useInviteUid();
    const [locale] = useLocale();
    const [isLoading, setLoading] = React.useState<boolean>(false);
    const [addressValidationData, setAddressValidationData] = React.useState<
        | {
              localeName: string;
              original: Partial<sway.IUser>;
              validated?: Partial<sway.IUser>;
          }
        | undefined
    >();
    const user: sway.IUser | undefined = useUser();

    if (!locale.name) {
        return <FullScreenLoading message={"Loading Sway Registration..."} />;
    }

    const swayFire = new SwayFireClient(
        firestore,
        toLocale(locale.name),
        firestoreConstructor,
    )

    if (
        !user ||
        !user.uid ||
        !user.email ||
        (user.isRegistrationComplete && user.locale?.district)
    )
        return <Dialog404 />;

    const [city, region, country] = splitLocaleName(locale.name);

    const initialValues: sway.IUser = {
        createdAt: user.createdAt || FieldValue.serverTimestamp(),
        updatedAt: user.updatedAt || FieldValue.serverTimestamp(),
        email: user.email || "", // from firebase
        uid: user.uid || "", // from firebase
        isRegistrationComplete: user.isRegistrationComplete || false,
        locale:
            user.locale ||
            ({
                name: locale.name,
                district: 0,
                congressionalDistrict: null,
                isSwayConfirmed: false,
                isRegisteredToVote: false,
            } as sway.IUserLocale),
        name: user.name || "",
        address1: user.address1 || "",
        address2: user.address2 || "",
        city: user.city
            ? titleize(fromLocaleNameItem(user.city))
            : fromLocaleNameItem(city),
        region: user.region
            ? user.region.length === 2
                ? STATE_CODES_NAMES[user.region.toUpperCase()]
                : titleize(fromLocaleNameItem(user.region))
            : fromLocaleNameItem(region),
        country: user.country
            ? titleize(fromLocaleNameItem(user.country))
            : fromLocaleNameItem(country),
        postalCode: user.postalCode || "",
        postalCodeExtension: user.postalCodeExtension || "",
        phone: user.phone || "",
        creationTime: user.creationTime || "",
        lastSignInTime: user.lastSignInTime || "",
    };

    const _findUserDistrict = (): number => {
        if (user.locale?.district) {
            return user.locale?.district;
        }
        return 0;
    };

    const handleSubmit = async (values: sway.IUser) => {
        if (!user.uid) return;

        setLoading(true);
        let localeName = "";
        try {
            localeName = toLocaleName(
                values.city,
                values.region,
                values.country,
            );
        } catch (error) {
            handleError(
                error,
                "Error validating form. City, state or country was blank.",
            );
            setLoading(false);
            return;
        }
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
                        localeName,
                        original: values,
                        validated: data.data as IValidateResponseData,
                    });
                } else {
                    if (IS_DEVELOPMENT) {
                        console.log("address validation empty response data");
                        console.log({ response });
                    }
                    setAddressValidationData({ localeName, original: values });
                }
            })
            .catch((error: Error) => {
                if (IS_DEVELOPMENT) {
                    console.log("error validating user address");
                    console.error(error);
                }
                setAddressValidationData({ localeName, original: values });
            });
    };

    const validateAddress = async ({
        localeName,
        original,
        validated,
    }: {
        localeName: string;
        original: Partial<sway.IUser>;
        validated?: Partial<sway.IUser> | undefined;
    }) => {
        if (!swayFire) {
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
            locale: {
                name: localeName,
                district: _findUserDistrict(),
                isSwayConfirmed: false,
                isRegisteredToVote: false,
                _city: _values.city,
                _region: _values.region,
                _country: _values.country,
            },
            invitedBy: isEmptyObject(inviteUid) ? "" : inviteUid,
        } as sway.IUser;

        // NOTE: Also creates user settings from DEFAULT_USER_SETTINGS
        const isUpdating = Boolean(
            user && user.uid && user.isRegistrationComplete === false,
        );
        const created = await swayFire
            .users(values.uid)
            .create(values, isUpdating);

        if (created) {
            notify({
                level: "info",
                title: "Registration Received",
                message: "Finding your legislative district.",
                duration: 0,
            });
            swayFire
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
                                        if (field.name === "localeName") {
                                            return (
                                                <ReduxLocaleSelector
                                                    key={field.name}
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
                                    style={{ color: swayWhite }}
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
                    localeName={addressValidationData.localeName}
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
