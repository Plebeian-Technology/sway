/** @format */

import { isFirebaseUser, IS_DEVELOPMENT } from "@sway/utils";
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
        IS_DEVELOPMENT && console.log("(dev) HOME - APP DRAWER (dev)");
        return (
            <AppDrawer user={user}>
                <Legislators user={user} />
            </AppDrawer>
        );
    }
    if (user && user.isAnonymous) {
        IS_DEVELOPMENT && console.log("(dev) HOME - ANON USER RENDER SIGNIN");
        return <SignIn />;
    }
    if (
        user &&
        !user.isAnonymous &&
        user.isRegistrationComplete &&
        !user.isEmailVerified
    ) {
        IS_DEVELOPMENT && console.log("(dev) HOME - USER EMAIL NOT VERIFIED");
        const needsActivationQS: string | null = new URLSearchParams(
            window.location.search,
        ).get("needsEmailActivation");
        if (needsActivationQS && needsActivationQS !== "1") {
            notify({
                level: "info",
                title: "Please verify your email.",
                message: "",
            });
        }
        return <SignIn />;
    }
    if (user && user.locales && !user.isRegistrationComplete) {
        IS_DEVELOPMENT &&
            console.log("(dev) HOME - USER REGISTRATION INTRODUCTION");

        return <SignIn />;
    }
    if (!user?.uid) {
        IS_DEVELOPMENT && console.log("(dev) HOME - RENDER SIGNIN");
        return <SignIn />;
    }
    if (
        user &&
        !isFirebaseUser(user) &&
        user.isRegistrationComplete === false
    ) {
        IS_DEVELOPMENT &&
            console.log(
                "(dev) HOME - NOT FIRE USER, BASE LOCALE - needs registration -",
            );

        return <SignIn />;
    }
    if (user && isFirebaseUser(user)) {
        IS_DEVELOPMENT && console.log("(dev) HOME - FIRE USER");

        return <SignIn />;
    }
    IS_DEVELOPMENT && console.log("(dev) HOME - LOADING");
    return <FullScreenLoading message={"Loading..."} />;
};
export default Home;
