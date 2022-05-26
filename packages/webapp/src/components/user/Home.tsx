/** @format */

import { ROUTES } from "@sway/constants";
import { isEmptyObject, isFirebaseUser, logDev } from "@sway/utils";
import { sendEmailVerification, User } from "firebase/auth";
import React, { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import { handleError, notify } from "../../utils";
import CenteredLoading from "../dialogs/CenteredLoading";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SignIn from "./SignIn";

interface IProps {
    user: sway.IUser | undefined;
}

const Home: React.FC<IProps> = ({ user }) => {
    const navigate = useNavigate();
    const [isLoaded, setLoaded] = useState<boolean>(false);

    logDev("HOME.user -", user);

    const isAuthedWithSway =
        user && user.isEmailVerified && user.locales && user.isRegistrationComplete;

    const isAuthedNOSway =
        user && user.isEmailVerified && isEmptyObject(user.locales) && !user.isRegistrationComplete;

    useEffect(() => {
        setLoaded(true);
    }, []);

    useEffect(() => {
        logDev("HOME.useEffect -", { isLoaded, isAuthedWithSway, isAuthedNOSway });
        if (isLoaded) {
            if (isAuthedWithSway) {
                navigate(ROUTES.legislators, { replace: true });
            } else if (isAuthedNOSway) {
                navigate(ROUTES.registration);
            } else if (user && !user?.isEmailVerified) {
                notify({
                    level: "info",
                    title: "Please verify your email address.",
                    message: "Click here to re-send the verification email.",
                    duration: 20000,
                    // @ts-ignore
                    onClick: () => sendEmailVerification(user as User).catch(handleError),
                });
                navigate(ROUTES.registration);
            }
        }
    }, [isLoaded, isAuthedWithSway, isAuthedNOSway]);

    if (isAuthedWithSway) {
        logDev("HOME - REDIRECT LEGISLATORS");
        return <CenteredLoading />;
    }
    if (isAuthedNOSway) {
        logDev("HOME - REDIRECT REGISTRATION");
        return <CenteredLoading />;
    }
    if (user && user.isAnonymous) {
        logDev("HOME - ANON USER RENDER SIGNIN");
        return <SignIn />;
    }
    if (user && !user.isAnonymous && user.isRegistrationComplete && !user.isEmailVerified) {
        logDev("HOME - USER EMAIL NOT VERIFIED");
        const needsActivationQS: string | null = new URLSearchParams(window.location.search).get(
            "needsEmailActivation",
        );
        if (needsActivationQS && needsActivationQS !== "1") {
            notify({
                level: "info",
                title: "Please verify your email.",
            });
        }
        return <SignIn />;
    }
    if (user && user.locales && !user.isRegistrationComplete) {
        logDev("HOME - USER REGISTRATION INTRODUCTION");

        return <SignIn />;
    }
    if (!user?.uid) {
        logDev("HOME - RENDER SIGNIN");
        return <SignIn />;
    }
    if (user && !isFirebaseUser(user) && user.isRegistrationComplete === false) {
        logDev("HOME - NOT FIRE USER, BASE LOCALE - needs registration -");

        return <SignIn />;
    }
    if (user && isFirebaseUser(user)) {
        logDev("HOME - FIRE USER");

        return <SignIn />;
    }
    logDev("HOME - LOADING");
    return <FullScreenLoading message={"Loading..."} />;
};
export default Home;
