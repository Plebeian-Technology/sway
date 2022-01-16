/** @format */
import { makeStyles } from "@mui/styles";

import { Button, Divider, Link, Theme, Typography } from "@mui/material";
import { CatchingPokemon } from "@mui/icons-material";
import {
    CLOUD_FUNCTIONS,
    CONGRESS_LOCALE,
    CONGRESS_LOCALE_NAME,
    COUNTRY_NAMES,
    NOTIFY_COMPLETED_REGISTRATION,
    SWAY_REDEEMING_INVITE_FROM_UID_COOKIE,
    SWAY_USER_REGISTERED,
} from "src/constants";
import SwayFireClient from "src/fire";
import {
    findLocale,
    findNotCongressLocale,
    fromLocaleNameItem,
    getStorage,
    isEmptyObject,
    logDev,
    removeStorage,
    setStorage,
    titleize,
    toFormattedLocaleName,
    toLocale,
    toLocaleName,
} from "src/utils";
import firebase from "firebase/app";
import { Form, Formik, FormikProps, FormikValues } from "formik";
import { useCallback, useState } from "react";
import { fire, sway } from "sway";
import * as Yup from "yup";
import { functions as swayFunctions } from "../../firebase";
import { useInviteUid, useUser } from "../../hooks";
import { handleError, notify, swayFireClient, SWAY_COLORS } from "../../utils";
import CenteredLoading from "../dialogs/CenteredLoading";
import Dialog404 from "../dialogs/Dialog404";
import SwaySvg from "../SwaySvg";
import AddressValidationDialog from "./AddressValidationDialog";
import RegistrationFields from "./RegistrationFields";

const useStyles = makeStyles((theme: Theme) => ({
    banner: {
        borderBottom: `3px solid ${SWAY_COLORS.secondaryDark}`,
        letterSpacing: 0,
    },
    button: {
        padding: theme.spacing(2),
        margin: theme.spacing(1),
        backgroundColor: SWAY_COLORS.primaryLight,
        color: SWAY_COLORS.white,
    },
    buttonContainer: {
        textAlign: "center",
    },
    divider: {
        margin: theme.spacing(2),
    },
    textContainer: {
        display: "flex",
        flexDirection: "column",
        margin: theme.spacing(1),
        padding: theme.spacing(1),
    },
    typography: {
        margin: theme.spacing(1),
    },
    submitButtonContainer: {
        margin: theme.spacing(2),
        textAlign: "center",
    },
    submitButton: { color: SWAY_COLORS.white },
    centeredTextContainer: {
        textAlign: "center",
        marginTop: 0,
    },
    errorSpan: {
        position: "absolute",
        bottom: 2,
        color: SWAY_COLORS.danger,
    },
    link: {
        color: SWAY_COLORS.black,
        fontWeight: "bold",
    },
    formHeader: { textAlign: "center", marginBottom: 2 },
}));

export const ADDRESS_FIELDS = ["address1", "address2", "postalCode"];

const REGISTRATION_FIELDS: sway.IFormField[] = [
    {
        name: "name",
        component: "text",
        type: "text",
        label: "Name (ex. Abraham Lincoln)",
        isRequired: true,
        autoComplete: "name",
    },
    // {
    //     name: "phone",
    //     component: "text",
    //     type: "tel",
    //     label: "Phone (ex. 1238675309)",
    //     isRequired: true,
    //     autoComplete: "tel-national",
    //     subLabel:
    //         "We'll send you a reminder to vote once per week. To opt-out go to 'Settings' after completing registration here.",
    // },
    // {
    //     name: "selectedLocale",
    //     component: "select",
    //     type: "text",
    //     label: "Location",
    //     isRequired: true,
    // },
    // {
    //     name: "country",
    //     component: "select",
    //     type: "text",
    //     label: "Country",
    //     isRequired: true,
    //     possibleValues: COUNTRY_NAMES.sort(),
    //     default: "United States",
    //     disabled: true,
    //     autoComplete: "shipping country-name",
    // },
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
    // {
    //     name: "city",
    //     component: "text",
    //     type: "text",
    //     label: "City",
    //     isRequired: true,
    //     autoComplete: "shipping address-level2",
    // },
    // {
    //     name: "regionCode",
    //     component: "select",
    //     type: "text",
    //     label: "State",
    //     possibleValues: Object.keys(STATE_CODES_NAMES).sort(),
    //     isRequired: true,
    //     autoComplete: "shipping address-level1",
    // },
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
    postalCode: Yup.string().required().length(5),
});

export interface IValidateResponseData {
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
    validated: IValidateResponseData;
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

    if (!user?.uid) return <Dialog404 />;

    const defaultUserLocales = () => {
        if (isEmptyObject(user.locales)) {
            if (user.city && user.region && user.country) {
                const localeName = toLocaleName(
                    user.city,
                    user.region,
                    user.country,
                );
                const loc = toLocale(localeName);
                if (!loc) return [];
                return [loc] as sway.IUserLocale[];
            }
            return [];
        }
        return user.locales;
    };

    const initialValues: sway.IUser = {
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
    };

    const handleUSPSValidationError = (
        localeName: string,
        values: sway.IUser,
    ) => {
        notify({
            level: "warning",
            title: "Failed USPS Validation",
            message:
                "We couldn't validate your address and may have trouble finding your representatives. Tap here to *cancel* and try again.",
            onClick: () => {
                window.location.reload();
            },
        });
        setTimeout(() => {
            setAddressValidationData({
                localeName: localeName,
                original: values,
                validated: values as IValidateResponseData,
            });
        }, 5000);
    };

    const handleSubmit = async (values: sway.IUser) => {
        logDev("Registration - submitting values to usps validation:", values);
        notify({
            level: "info",
            title: "Checking your address with USPS",
        });

        const localeName = isEmptyObject(values.locales)
            ? toLocaleName(values.city, values.region, values.country)
            : findNotCongressLocale(values.locales)?.name;

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
                    setLoading(false);
                    logDev("address validation empty response data", {
                        response,
                    });
                    handleUSPSValidationError(localeName, values);
                }
            })
            .catch((error: Error) => {
                console.error(error);
                setLoading(false);
                logDev("error validating user address with USPS");
                handleUSPSValidationError(localeName, values);
            });
    };

    const onAddressValidatedByUSPS = async ({
        original,
        validated,
        localeName,
    }: {
        original: Partial<sway.IUser>;
        validated: IValidateResponseData;
        localeName: string;
    }) => {
        setLoading(true);
        logDev("Address Validated, Original vs. USPS Validated -", {
            original,
            validated,
            localeName,
        });

        const { city } = validated;
        const { region, regionCode, country } = original;
        if (!city || !region || !regionCode || !country) return;

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

        const created = await fireClient.users(values.uid).create(values, true);

        logDev("Registration - user created -", created);

        if (created) {
            await fireClient.users(values.uid).createUserSettings(created);

            logDev("Creating user invites object.");
            await fireClient
                .userInvites(values.uid)
                .upsert({})
                .catch(handleError);

            handleUserCreatedListenForLegislators(fireClient, created);
        } else {
            setLoading(false);
            handleError(
                new Error("Error registering user."),
                "Failed to register with Sway. Invalid information.",
            );
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
                                localStorage.removeItem(
                                    NOTIFY_COMPLETED_REGISTRATION,
                                );
                                setTimeout(() => {
                                    window.location.href = `/legislators?${NOTIFY_COMPLETED_REGISTRATION}=1`;
                                }, 1000);
                            } else {
                                setTimeout(() => {
                                    window.location.href =
                                        "/?needsEmailActivation=1";
                                }, 1000);
                            }
                        }
                    } catch (error) {
                        handleError(
                            error as Error,
                            "Failed to register with Sway. Please try again.",
                        );
                        setLoading(false);
                    }
                },
            );
    };

    const isTextField = useCallback(
        (field: sway.IFormField) => field.component === "text",
        [],
    );

    logDev("Registration - render Formik", initialValues);
    return (
        <div className={"registration-container"}>
            <div id="subcontainer">
                <div className={classes.textContainer}>
                    <Typography
                        className={classes.typography}
                        component="h6"
                        variant="h6"
                    >
                        Sway requires additional information about you in order
                        to match you with your representatives.
                    </Typography>
                    <Typography
                        className={classes.typography}
                        component="h6"
                        variant="h6"
                    >
                        We take privacy very seriously. If you have any
                        questions about what happens to your data please see our
                        privacy policy, or contact our internal privacy auditor
                        at{" "}
                        <Link
                            className={classes.link}
                            href="mailto:privacy@sway.vote"
                        >
                            privacy@sway.vote
                        </Link>
                        .
                    </Typography>
                    <Typography
                        className={classes.typography}
                        component="h6"
                        variant="h6"
                    >
                        We also offer virtual walkthroughs of Sway, showcasing
                        where and how your data is stored. To schedule a
                        walkthrough send an email to{" "}
                        <Link
                            className={classes.link}
                            href="mailto:privacy@sway.vote"
                        >
                            privacy@sway.vote
                        </Link>
                        .
                    </Typography>
                    {/* <Typography
                                    className={classes.typography}
                                    component="p"
                                    variant="body1"
                                    color="textPrimary"
                                >
                                    If you want to see more about how Sway
                                    works under-the-hood, code for Sway is
                                    open-source and publicly viewable and
                                    editable on Github at{" "}
                                    <Link className={classes.link} href="https://www.github.com/plebeian-technologies/sway">
                                        https://www.github.com/plebeian-technologies/sway
                                    </Link>
                                    .
                                </Typography> */}
                </div>
                <Divider className={classes.divider} />
                <div className={classes.textContainer}>
                    <Typography
                        className={classes.typography}
                        style={{ marginTop: 1, marginBottom: 1 }}
                        component="h6"
                        variant="h6"
                    >
                        If you are registered to vote, please complete each of
                        the following fields to match, as closely as possible,
                        what is on your voter registration.
                    </Typography>
                    <Typography
                        className={classes.typography}
                        style={{ marginTop: 1, marginBottom: 1 }}
                        component="h6"
                        variant="h6"
                    >
                        If you are not registered to vote, it is not required
                        but is{" "}
                        <span style={{ fontWeight: "bold" }}>strongly</span>{" "}
                        recommended. You can register to vote
                        <Link
                            className={classes.link}
                            target={"_blank"}
                            href="https://www.vote.org/register-to-vote/"
                        >
                            {" here."}
                        </Link>
                    </Typography>
                    <Typography
                        className={classes.typography}
                        style={{ marginTop: 1, marginBottom: 1 }}
                        component="h6"
                        variant="h6"
                    >
                        You can find your current voter registration
                        <Link
                            className={classes.link}
                            target={"_blank"}
                            href="https://www.vote.org/am-i-registered-to-vote/"
                        >
                            {" here."}
                        </Link>
                    </Typography>
                </div>
                <Divider className={classes.divider} />
                <div className={classes.textContainer}>
                    <Typography
                        className={classes.typography}
                        style={{ marginTop: 1, marginBottom: 1 }}
                        component="h6"
                        variant="h6"
                    >
                        If you want to see more about how Sway works
                        under-the-hood, code for Sway is available on{" "}
                        {
                            <Button
                                className={classes.button}
                                style={{ padding: "0.5em 1em", margin: 0 }}
                                variant="contained"
                                color="primary"
                                onClick={() =>
                                    window.open(
                                        "https://github.com/Plebeian-Technology/sway",
                                    )
                                }
                                startIcon={
                                    <SwaySvg
                                        src={"/icons/github.svg"}
                                        containerStyle={{ margin: "0px" }}
                                    />
                                }
                            >
                                {"Github"}
                            </Button>
                        }
                    </Typography>
                </div>
            </div>
            <Divider className={classes.divider} />
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
