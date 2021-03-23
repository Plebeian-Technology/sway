/** @format */

import { isFirebaseUser, logDev } from "@sway/utils";
import React from "react";
import { sway } from "sway";
import { notify } from "../../utils";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import AppDrawer from "../drawer/AppDrawer";
import Legislators from "../legislator/Legislators";
// import RegistrationIntroduction from "./RegistrationIntroduction";
import SignIn from "./SignIn";

interface IProps {
    user: sway.IUser | undefined;
}

const Home: React.FC<IProps> = ({ user }) => {
    if (
        user &&
        user.locales &&
        user.isRegistrationComplete &&
        user.isEmailVerified
    ) {
        logDev("HOME - APP DRAWER (dev)");
        return (
            <AppDrawer user={user}>
                <Legislators user={user} />
            </AppDrawer>
        );
    }
    if (user && user.isAnonymous) {
        logDev("HOME - ANON USER RENDER SIGNIN");
        return <SignIn />;
    }
    if (
        user &&
        !user.isAnonymous &&
        user.isRegistrationComplete &&
        !user.isEmailVerified
    ) {
        logDev("HOME - USER EMAIL NOT VERIFIED");
        const needsActivationQS: string | null = new URLSearchParams(
            window.location.search,
        ).get("needsEmailActivation");
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
    if (
        user &&
        !isFirebaseUser(user) &&
        user.isRegistrationComplete === false
    ) {
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
