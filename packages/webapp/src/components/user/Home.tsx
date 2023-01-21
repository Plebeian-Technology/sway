/** @format */

import { ROUTES } from "@sway/constants";
import { isFirebaseUser, logDev } from "@sway/utils";
import { useEffect, useState } from "react";
import { useDispatch } from "react-redux";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import { useFirebaseUser } from "../../hooks";
import { useSwayFireClient } from "../../hooks/useSwayFireClient";
import { setUser } from "../../redux/actions/userActions";
import { handleError, notify } from "../../utils";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SignIn from "./SignIn";

interface IProps {
    user: sway.IUser | undefined;
}

const Home: React.FC<IProps> = ({ user }) => {
    const navigate = useNavigate();
    const dispatch = useDispatch();
    const swayFireClient = useSwayFireClient();
    const [firebaseUser] = useFirebaseUser();
    const [isLoaded, setLoaded] = useState<boolean>(false);

    logDev("HOME.user -", user);

    const isAuthedNoEmailVerified = user && firebaseUser && !firebaseUser?.emailVerified;
    const isAuthedFirebaseOnlyEmailVerified =
        user && !user?.isEmailVerified && firebaseUser && firebaseUser?.emailVerified;
    const isAuthedNOSway =
        user && user.isEmailVerified && user.locales === undefined && !user.isRegistrationComplete;
    const isAuthedWithSway =
        user && user.isEmailVerified && user.locales && user.isRegistrationComplete;

    useEffect(() => {
        setLoaded(true);
    }, []);

    useEffect(() => {
        logDev("HOME.useEffect -", {
            isLoaded,
            isAuthedWithSway,
            isAuthedNOSway,
            user,
            firebaseUser,
        });

        let timeout: NodeJS.Timeout | undefined = undefined;

        if (isLoaded) {
            if (isAuthedFirebaseOnlyEmailVerified) {
                logDev(
                    "HOME.useEffect - isAuthedFirebaseOnlyEmailVerified - get user from firebase and dispatch to redux",
                );
                const uid = user.uid || firebaseUser.uid;
                swayFireClient
                    .users(uid)
                    .update({
                        ...user,
                        isEmailVerified: firebaseUser.emailVerified,
                    })
                    .then(async (updated) => {
                        if (!updated) return;

                        const userWithSettings = await swayFireClient.users(uid).getWithSettings();
                        if (!userWithSettings) return;
                        dispatch(
                            setUser({
                                ...userWithSettings,
                                user: updated,
                            }),
                        );
                    })
                    .catch(handleError);
            } else if (isAuthedNoEmailVerified) {
                logDev(
                    `HOME.useEffect - isAuthedNoEmailVerified - navigate to - ${ROUTES.signin}?needsEmailActivation=1`,
                );
                navigate(`${ROUTES.signin}?needsEmailActivation=1`);
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
                    navigate(ROUTES.registration);
                }, 3000);
            }
        }
        return () => {
            if (timeout) {
                clearTimeout(timeout);
            }
        };
    }, [
        isLoaded,
        isAuthedWithSway,
        isAuthedNOSway,
        isAuthedNoEmailVerified,
        isAuthedFirebaseOnlyEmailVerified,
    ]);

    if (isAuthedWithSway) {
        logDev("HOME - REDIRECT LEGISLATORS - LOADING SPINNER");
        return <FullScreenLoading />;
    }
    if (isAuthedNOSway) {
        logDev("HOME - REDIRECT REGISTRATION - LOADING SPINNER");
        return <FullScreenLoading />;
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
        if (needsActivationQS && needsActivationQS === "1") {
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
