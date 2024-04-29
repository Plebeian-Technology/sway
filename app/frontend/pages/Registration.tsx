/** @format */

import {
    CONGRESS_LOCALE,
    CONGRESS_LOCALE_NAME,
    NOTIFY_COMPLETED_REGISTRATION,
} from "../sway_constants";

import { Form, Formik } from "formik";
import { useCallback, useMemo, useState } from "react";
import { Badge, Button } from "react-bootstrap";
import { FiExternalLink, FiGithub } from "react-icons/fi";
import { useDispatch } from "react-redux";
import { sway } from "sway";
import * as Yup from "yup";
import { useLogout } from "../hooks/users/useLogout";

import { isEmpty } from "lodash";
import toast from "react-hot-toast";
import Dialog404 from "../components/dialogs/Dialog404";
import FullScreenLoading from "../components/dialogs/FullScreenLoading";
import RegistrationFields from "../components/user/RegistrationFields";
import { useAxiosPost } from "../hooks/useAxios";
import { setUser } from "../redux/actions/userActions";
import {
    SWAY_STORAGE,
    findLocale,
    findNotCongressLocale,
    fromLocaleNameItem,
    handleError,
    isEmptyObject,
    localRemove,
    localSet,
    logDev,
    notify,
    toFormattedLocaleName,
    toLocale,
    toLocaleName,
} from "../sway_utils";
import { router } from "@inertiajs/react";

const DEFAULT_COORDINATES = { lat: undefined, lng: undefined };

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

interface IProps {
    user: sway.IUserWithSettingsAdmin
}

const Registration: React.FC<IProps> = ({  user }) => {
    const dispatch = useDispatch();

    const logout = useLogout();

    const [isLoading, setLoading] = useState<boolean>(false);
    const [loadingMessage, setLoadingMessage] = useState<string>("");
    const [coordinates, setCoordinates] = useState<{
        lat: number | undefined;
        lng: number | undefined;
    }>(DEFAULT_COORDINATES);

    const defaultUserLocales = useMemo(() => {
        if (user.address && isEmpty(user.locales)) {
            if (user.address.city && user.address.stateProvinceCode && user.address.country) {
                const localeName = toLocaleName(user.address);
                const loc = toLocale(localeName);
                if (!loc) return [];
                return [loc] as sway.IUserLocale[];
            } else {
                return [];
            }
        } else {
            return user.locales;
        }
    }, [user.locales, user.address]);

    const initialValues: sway.IUser = useMemo(
        () => ({
            id: user.id || -1,
            // name: user.name || "",
            email: user.email || "",
            phone: user.phone ? user.phone : "",
            isRegisteredToVote: false,
            isSwayConfirmed: false,
            isEmailVerified: user.isEmailVerified ?? false,
            isPhoneVerified: user.isPhoneVerified ?? false,
            isRegistrationComplete: user.isRegistrationComplete || false,
            locales: defaultUserLocales,
            address: user.address,
        }),
        [user, defaultUserLocales],
    );

    const notifyLocaleNotAvailable = useCallback((locale: sway.ILocale) => {
        const formatted = toFormattedLocaleName(locale.name);
        const formattedCity = fromLocaleNameItem(locale.city);

        setLoadingMessage(
            `We have no data for ${formatted} but you can still use Sway with your Congressional representatives.\nWe'll update your account once data for ${formattedCity} is added.`,
        );
    }, []);

    const { post: updateUser } = useAxiosPost<sway.IUser>("/users/update");

    const findUserLocales = useCallback(
        async (newValues: sway.IUser, locale: sway.ILocale, toastId: string) => {
            logDev("Registration.findUserLocales - calling cloud function -", {
                newValues,
                locale,
                coordinates,
            });

            // const updater = httpsCallable(functions, CLOUD_FUNCTIONS.createUserLegislators);
            const updated = await updateUser({
                id: user.id,
                locale,
                latitude: coordinates.lat,
                longitude: coordinates.lng,
            });

            setLoading(false);

            if (updated) {
                localSet(SWAY_STORAGE.Local.User.Registered, "true");
                localRemove(SWAY_STORAGE.Local.User.InvitedBy);
                if (updated?.locales.find((l) => l.name === locale.name)) {
                    localRemove(NOTIFY_COMPLETED_REGISTRATION);
                    toastId && toast.dismiss(toastId);
                    notify({
                        level: "success",
                        title: "Legislators Found!",
                        message: "Navigating to your legislators...",
                    });

                    dispatch(setUser(updated as sway.IUserWithSettingsAdmin));

                    setTimeout(() => {
                        // window.location.replace(`/legislators?${NOTIFY_COMPLETED_REGISTRATION}=1`);
                        router.visit(`/legislators?${NOTIFY_COMPLETED_REGISTRATION}=1`, {
                            replace: true,
                        });
                    }, 3000);
                } else {
                    toastId && toast.dismiss(toastId);
                    notify({
                        level: "error",
                        title: "Failed to find legislators.",
                        message: "Try refreshing and hitting the submit button again.",
                    });
                }
            }
        },
        [coordinates, dispatch, updateUser, user.id],
    );

    const handleSubmit = useCallback(
        async (values: sway.IUser) => {
            setLoading(true);
            const toastId = notify({
                level: "info",
                title: "Finding your representatives.",
                message:
                    "Matching your address to your local and congressional legislators may take a minute...",
                duration: 0,
            });

            const localeName = isEmptyObject(values.locales)
                ? toLocaleName(values.address)
                : findNotCongressLocale(values.locales)?.name;

            const locale = findLocale(localeName) || CONGRESS_LOCALE;

            if (locale.name === CONGRESS_LOCALE_NAME) {
                notifyLocaleNotAvailable(locale);
            }

            const newValues = {
                ...values,
                id: user.id,
                isEmailVerified: Boolean(user.isEmailVerified),
                locales: [locale] as sway.IUserLocale[],
                isRegistrationComplete: true,
            } as sway.IUser;

            logDev("Registration - submitting newValues to update user:", newValues);
            try {
                const updated = await updateUser(newValues);
                logDev("Registration - user updated -", updated);

                if (updated) {
                    await findUserLocales(newValues, locale, toastId);
                } else {
                    toast?.dismiss(toastId);
                    setLoading(false);
                    notify({
                        level: "error",
                        title: "Failed to find legislators.",
                        message: "Please refresh the page and try again.",
                    });
                }
            } catch (error) {
                toast?.dismiss(toastId);
                setLoading(false);
                handleError(error as Error, "Failed to register user.");
            }
        },
        [findUserLocales, notifyLocaleNotAvailable, updateUser, user.id, user.isEmailVerified],
    );

    const openUrl = useCallback((url: string) => {
        window.open(url, "_blank");
    }, []);

    if (!user?.id) return <Dialog404 />;

    logDev("Registration - render Formik with initial values -", initialValues);
    return (
        <div className="row">
            <div className="col">
                <div>
                    <p>
                        Sway requires additional information about you in order to match you with
                        your representatives.
                    </p>
                </div>
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
                        <div className="row align-items-center">
                            <div className="col text-start">
                                <Button variant="outline-light" onClick={logout}>
                                    Cancel
                                </Button>
                            </div>
                            <div className="col text-end">
                                <Button
                                    disabled={isLoading}
                                    type="submit"
                                    className="my-2"
                                >
                                    Submit
                                </Button>
                            </div>
                        </div>
                    </Form>
                </Formik>
            </div>
            <hr />
            <div>
                <div className="my-1">
                    If you are registered to vote, please complete each of the following fields to
                    match - as closely as possible - what is on your voter registration.
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
            <div className="pb-5">
                {/* <p>
                    We take privacy very seriously. If you have any questions about what happens to
                    your data please see our privacy policy, or contact our internal privacy auditor
                    at{" "}
                    <Badge
                        pill
                        className="pointer"
                        bg="info"
                        onClick={() => handleCopy("privacy@sway.vote")}
                    >
                        <FiCopy />
                        &nbsp;privacy@sway.vote
                    </Badge>
                </p> */}
                {/* <hr /> */}
                <p className="my-1">
                    If you want to see more about how Sway works under-the-hood, code for Sway is
                    available on&nbsp;
                    {
                        <Badge
                            pill
                            className="pointer"
                            bg="info"
                            onClick={() => openUrl("https://github.com/Plebeian-Technology/sway")}
                        >
                            <FiGithub />
                            &nbsp;Github
                        </Badge>
                    }
                </p>
            </div>
        </div>
    );
};

export default Registration;
