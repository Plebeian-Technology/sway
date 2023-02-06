/** @format */

import { ROUTES } from "@sway/constants";
import { isFirebaseUser, logDev } from "@sway/utils";
import { useEffect, useMemo, useState } from "react";
import { useDispatch } from "react-redux";
import { useLocation, useNavigate } from "react-router-dom";
import { useFirebaseUser, useUser } from "../../hooks";
import { useSwayFireClient } from "../../hooks/useSwayFireClient";
import { notify } from "../../utils";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SignIn from "./SignIn";

const Home: React.FC = () => {
    const navigate = useNavigate();
    const { search } = useLocation();
    const dispatch = useDispatch();
    const fire = useSwayFireClient();
    const [firebaseUser] = useFirebaseUser();
    const user = useUser();
    const uid = useMemo(() => firebaseUser?.uid || user?.uid, [firebaseUser?.uid, user?.uid]);
    const [isLoaded, setLoaded] = useState<boolean>(false);

    logDev("HOME.user -", user);

    const isAuthedNoEmailVerified = Boolean(user && !firebaseUser?.emailVerified);
    const isAuthedFirebaseOnlyEmailVerified = Boolean(
        !user?.isEmailVerified && firebaseUser?.emailVerified,
    );
    const isAuthedNOSway = Boolean(user?.isEmailVerified && !user?.isRegistrationComplete);
    const isAuthedWithSway = Boolean(user?.isEmailVerified && user?.isRegistrationComplete);

    useEffect(() => {
        setLoaded(true);
    }, []);

    useEffect(() => {
        if (!isLoaded || !uid) return;

        logDev("HOME.useEffect -", {
            isLoaded,
            isAuthedWithSway,
            isAuthedNOSway,
            isAuthedNoEmailVerified,
            isAuthedFirebaseOnlyEmailVerified,
        });

        let timeout: NodeJS.Timeout | undefined = undefined;

        if (isAuthedNoEmailVerified) {
            logDev(
                `HOME.useEffect - isAuthedNoEmailVerified - navigate to - ${ROUTES.signin}?needsEmailActivation=1`,
            );
            navigate(`${ROUTES.signin}?needsEmailActivation=1`, { replace: true });
        } else if (isAuthedWithSway) {
            logDev(
                `HOME.useEffect - isAuthedWithSway - navigate to - ${ROUTES.legislators}, { replace: true }`,
            );
            navigate(ROUTES.legislators, { replace: true });
        } else if (isAuthedNOSway) {
            // Cancel navigating here
            timeout = setTimeout(() => {
                logDev(
                    `HOME.useEffect - isAuthedNOSway - navigate to - ${ROUTES.registration} REGISTRATION`,
                );
                navigate(ROUTES.registration, { replace: true });
            }, 3000);
        }
        return () => {
            if (timeout) {
                clearTimeout(timeout);
            }
        };
    }, [
        uid,
        isLoaded,
        isAuthedWithSway,
        isAuthedNOSway,
        isAuthedNoEmailVerified,
        isAuthedFirebaseOnlyEmailVerified,
        dispatch,
        fire,
        firebaseUser?.emailVerified,
        navigate,
    ]);

    if (isAuthedWithSway) {
        logDev("HOME - REDIRECT LEGISLATORS - LOADING SPINNER");
        return <FullScreenLoading />;
    }
    if (isAuthedNOSway) {
        logDev("HOME - REDIRECT REGISTRATION - LOADING SPINNER");
        return <FullScreenLoading />;
    }
    if (user?.isAnonymous) {
        logDev("HOME - ANON USER RENDER SIGNIN");
        return <SignIn />;
    }
    if (!user?.isAnonymous && user.isRegistrationComplete && !user.isEmailVerified) {
        logDev("HOME - USER EMAIL NOT VERIFIED");
        const needsActivationQS: string | null = new URLSearchParams(search).get(
            "needsEmailActivation",
        );
        if (needsActivationQS && needsActivationQS === "1") {
            notify({
                level: "info",
                title: "Please verify your email.",
            });
        }
        return <SignIn />;
    }
    if (user?.locales && !user.isRegistrationComplete) {
        logDev("HOME - USER REGISTRATION INTRODUCTION");

        return <SignIn />;
    }
    if (!user?.uid) {
        logDev("HOME - RENDER SIGNIN");
        return <SignIn />;
    }
    if (!isFirebaseUser(user) && user.isRegistrationComplete === false) {
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
