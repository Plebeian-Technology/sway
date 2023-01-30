/** @format */

import {
    CLOUD_FUNCTIONS,
    CONGRESS_LOCALE,
    CONGRESS_LOCALE_NAME,
    COUNTRY_NAMES,
    NOTIFY_COMPLETED_REGISTRATION,
    SwayStorage,
} from "@sway/constants";
import SwayFireClient from "@sway/fire";
import {
    findLocale,
    findNotCongressLocale,
    fromLocaleNameItem,
    isEmptyObject,
    logDev,
    titleize,
    toFormattedLocaleName,
    toLocale,
    toLocaleName,
} from "@sway/utils";
import copy from "copy-to-clipboard";
import { httpsCallable, HttpsCallableResult } from "firebase/functions";
import { Form, Formik } from "formik";
import { useMemo, useState } from "react";
import { Badge, Button, Image } from "react-bootstrap";
import { FiCopy, FiExternalLink, FiGithub } from "react-icons/fi";
import { useDispatch } from "react-redux";
import { useNavigate } from "react-router";
import { toast } from "react-toastify";
import { sway } from "sway";
import * as Yup from "yup";
import { functions } from "../../firebase";
import { useFirebaseUser, useInviteUid, useLogout, useUser } from "../../hooks";
import { setUser } from "../../redux/actions/userActions";
import { handleError, localGet, localRemove, localSet, notify, swayFireClient } from "../../utils";
import Dialog404 from "../dialogs/Dialog404";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import RegistrationFields from "./RegistrationFields";

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
    {
        name: "address",
        component: "text",
        type: "text",
        label: "Address (ex. 1 W Elm St)",
        isRequired: true,
        autoComplete: "shipping address",
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

const Registration: React.FC = () => {
    const navigate = useNavigate();
    const dispatch = useDispatch();
    const logout = useLogout();
    const [firebaseUser] = useFirebaseUser();
    const invitedByUid = useInviteUid();
    const [isLoading, setLoading] = useState<boolean>(false);
    const [loadingMessage, setLoadingMessage] = useState<string>("");
    const [coordinates, setCoordinates] = useState<{
        lat: number | undefined;
        lng: number | undefined;
    }>({ lat: undefined, lng: undefined });
    const user: sway.IUser | undefined = useUser();

    if (!user?.uid) return <Dialog404 />;

    const defaultUserLocales = () => {
        if (isEmptyObject(user.locales)) {
            if (user.city && user.region && user.country) {
                const localeName = toLocaleName(user.city, user.region, user.country);
                const loc = toLocale(localeName);
                if (!loc) return [];
                return [loc] as sway.IUserLocale[];
            }
            return [];
        }
        return user.locales;
    };

    const initialValues: sway.IUser = useMemo(
        () => ({
            createdAt: undefined, // set in fire_users
            updatedAt: undefined, // set in fire_users
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
        }),
        [JSON.stringify(user)],
    );

    const notifyLocaleNotAvailable = (locale: sway.ILocale) => {
        const formatted = toFormattedLocaleName(locale.name);
        const formattedCity = fromLocaleNameItem(locale.city);

        setLoadingMessage(
            `We have no data for ${formatted} but you can still use Sway with your Congressional representatives.\nWe'll update your account once data for ${formattedCity} is added.`,
        );
    };

    const handleSubmit = async (values: sway.IUser) => {
        setLoading(true);
        const toastId = notify({
            level: "info",
            title: "Finding your representatives.",
            message:
                "Matching your address to your local and congressional legislators may take a minute...",
            duration: 0,
        });

        const localeName = isEmptyObject(values.locales)
            ? toLocaleName(values.city, values.region, values.country)
            : findNotCongressLocale(values.locales)?.name;

        const locale = findLocale(localeName) || CONGRESS_LOCALE;
        const fireClient = swayFireClient(locale);

        if (locale.name === CONGRESS_LOCALE_NAME) {
            notifyLocaleNotAvailable(locale);
        }

        const newValues = {
            ...values,
            uid: user.uid,
            isEmailVerified: Boolean(user.isEmailVerified || firebaseUser?.emailVerified),
            invitedBy:
                user.invitedBy || isEmptyObject(invitedByUid)
                    ? localGet(SwayStorage.Local.User.InvitedBy)
                    : invitedByUid,
            locales: [locale] as sway.IUserLocale[],
            isRegistrationComplete: true,
        } as sway.IUser;

        logDev("Registration - submitting newValues to update user:", newValues);
        try {
            const updated = await fireClient.users(user.uid).create(newValues, true);
            logDev("Registration - user updated -", updated);

            if (updated) {
                await findUserLocales(fireClient, newValues, locale, toastId);
            } else {
                toastId && toast.dismiss(toastId);
                setLoading(false);
                notify({
                    level: "error",
                    title: "Failed to find legislators.",
                    message: "Please refresh the page and try again.",
                });
            }
        } catch (error) {
            toastId && toast.dismiss(toastId);
            console.error(error);
            setLoading(false);
            handleError(error as Error, "Failed to register user.");
        }
    };

    const findUserLocales = async (
        fireClient: SwayFireClient,
        newValues: sway.IUser,
        locale: sway.ILocale,
        toastId: string,
    ) => {
        logDev("Registration.findUserLocales - calling cloud function -", {
            newValues,
            locale,
            coordinates,
        });
        await fireClient.userInvites(newValues.uid).upsert({}).catch(console.error);

        const updater = httpsCallable(functions, CLOUD_FUNCTIONS.createUserLegislators);
        const updated = (await updater({
            uid: user.uid,
            locale,
            lat: coordinates.lat,
            lng: coordinates.lng,
        })) as HttpsCallableResult<sway.IUser | null>;

        setLoading(false);

        localSet(SwayStorage.Local.User.Registered, "1");
        localRemove(SwayStorage.Local.User.InvitedBy);
        if (updated.data?.locales.find((l) => l.name === locale.name)) {
            localRemove(NOTIFY_COMPLETED_REGISTRATION);
            toastId && toast.dismiss(toastId);
            notify({
                level: "success",
                title: "Legislators Found!",
                message: "Navigating to your legislators...",
            });

            dispatch(
                setUser({
                    user: updated.data,
                } as sway.IUserWithSettingsAdmin),
            );

            setTimeout(() => {
                // window.location.replace(`/legislators?${NOTIFY_COMPLETED_REGISTRATION}=1`);
                navigate(`/legislators?${NOTIFY_COMPLETED_REGISTRATION}=1`, { replace: true });
            }, 3000);
        } else {
            toastId && toast.dismiss(toastId);
            notify({
                level: "error",
                title: "Failed to find legislators.",
                message: "Try refreshing and hitting the submit button again.",
            });
        }
    };

    const openUrl = (url: string) => {
        window.open(url, "_blank");
    };

    const handleCopy = (toCopy: string): string => {
        copy(toCopy, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: `Copied ${toCopy} to clipboard.`,
                }),
        });
        return "";
    };

    logDev("Registration - render Formik with initial values -", initialValues);
    return (
        <div className={"min-vh-100 min-vw-100 row registration"}>
            <div className="col-lg-3 col-1">&nbsp;</div>
            <div className="col-lg-6 col-10">
                <div className="row py-3 align-items-center">
                    <div className="col-2">&nbsp;</div>
                    <div className="col-8 text-center justify-content-center align-items-center">
                        <Image
                            thumbnail
                            roundedCircle
                            src={"/logo300.png"}
                            style={{ maxWidth: 100 }}
                        />
                        <div className="my-2">{user.email}</div>
                        <Button variant="outline-light" onClick={logout}>
                            Logout
                        </Button>
                    </div>
                    <div className="col-2">&nbsp;</div>
                </div>
                <hr />
                <div>
                    <p>
                        Sway requires additional information about you in order to match you with
                        your representatives.
                    </p>
                </div>
                <hr />
                <div>
                    <div className="my-1">
                        If you are registered to vote, please complete each of the following fields
                        to match - as closely as possible - what is on your voter registration.
                    </div>
                    <hr />
                    <div className="my-1">
                        If you are not registered to vote, it is not required by Sway, but is{" "}
                        <span className="bold">strongly</span> recommended. You can register to
                        vote&nbsp;
                        <Badge
                            pill
                            className="pointer"
                            bg="info"
                            onClick={() => openUrl("https://www.vote.org/register-to-vote/")}
                        >
                            <FiExternalLink />
                            &nbsp;here
                        </Badge>
                    </div>
                    <div className="mt-2 mb-1">
                        You can find your current voter registration&nbsp;
                        <Badge
                            pill
                            className="pointer"
                            bg="info"
                            onClick={() => openUrl("https://www.vote.org/am-i-registered-to-vote/")}
                        >
                            <FiExternalLink />
                            &nbsp;here
                        </Badge>
                    </div>
                </div>
                <hr />
                <Formik
                    initialValues={initialValues}
                    onSubmit={handleSubmit}
                    validationSchema={VALIDATION_SCHEMA}
                    enableReinitialize={true}
                >
                    <Form>
                        {isLoading && <FullScreenLoading message={loadingMessage} />}
                        <RegistrationFields
                            user={user}
                            isLoading={isLoading}
                            setLoading={setLoading}
                            fields={REGISTRATION_FIELDS}
                            setCoordinates={setCoordinates}
                        />
                        <Button disabled={isLoading} size="lg" type="submit" className="my-2">
                            Find Representatives
                        </Button>
                    </Form>
                </Formik>
                <hr />
                <div className="pb-5">
                    <p>
                        We take privacy very seriously. If you have any questions about what happens
                        to your data please see our privacy policy, or contact our internal privacy
                        auditor at{" "}
                        <Badge
                            pill
                            className="pointer"
                            bg="info"
                            onClick={() => handleCopy("privacy@sway.vote")}
                        >
                            <FiCopy />
                            &nbsp;privacy@sway.vote
                        </Badge>
                    </p>
                    <hr />
                    <p className="my-1">
                        If you want to see more about how Sway works under-the-hood, code for Sway
                        is available on&nbsp;
                        {
                            <Badge
                                pill
                                className="pointer"
                                bg="info"
                                onClick={() =>
                                    openUrl("https://github.com/Plebeian-Technology/sway")
                                }
                            >
                                <FiGithub />
                                &nbsp;Github
                            </Badge>
                        }
                    </p>
                </div>
            </div>
            <div className="col-lg-3 col-1">&nbsp;</div>
        </div>
    );
};

export default Registration;
