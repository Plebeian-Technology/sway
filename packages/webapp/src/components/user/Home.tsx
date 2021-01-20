/** @format */

import React from "react";
import { sway } from "sway";
import { IS_DEVELOPMENT } from "../../utils";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import AppDrawer from "../drawer/AppDrawer";
import Legislators from "../legislator/Legislators";
import RegistrationIntroduction from "./RegistrationIntroduction";
import SignIn from "./SignIn";

interface IProps {
    locale: sway.ILocale;
    user: sway.IUser | undefined;
}

const Home: React.FC<IProps> = ({ user, locale }) => {
    if (user && user.locale && user.isRegistrationComplete) {
        IS_DEVELOPMENT && console.log("HOME - APP DRAWER (dev)");
        return (
            <AppDrawer locale={locale} user={user}>
                <Legislators locale={locale} user={user} />
            </AppDrawer>
        );
    }
    if (user && user.isAnonymous) {
        IS_DEVELOPMENT && console.log("HOME - ANON USER RENDER SIGNIN (dev)");
        return <SignIn />;
    }
    if (user && user.locale && !user.isRegistrationComplete) {
        IS_DEVELOPMENT &&
            console.log("HOME - USER REGISTRATION INTRODUCTION (dev)") &&
            console.log(user);

        return <RegistrationIntroduction user={user} />;
    }
    if (user && user.creationTime && !user.locale && locale.name && !user.isRegistrationComplete) {
    // if (user && user.metadata.lastSignInTime === user.metadata.creationTime) {
        IS_DEVELOPMENT &&
            console.log(
                "HOME - FIRE USER, BASE LOCALE - needs registration - (dev)",
                user,
            );

        return <RegistrationIntroduction user={user} />;
    }
    if (!user?.uid) {
        IS_DEVELOPMENT && console.log("HOME - RENDER SIGNIN (dev)");
        return <SignIn />;
    }
    // if (user.uid && locale) {
    //     return <SignIn />;
    // }
    IS_DEVELOPMENT && console.log("HOME - LOADING (dev)");
    return <FullScreenLoading message={"Loading..."} />;
};
export default Home;
