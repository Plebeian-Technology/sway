/** @format */

import { logDev } from "@sway/utils";
import React, { lazy, Suspense } from "react";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import { sway } from "sway";
import BillOfTheWeek from "../bill/BillOfTheWeek";
import BillRoute from "../bill/BillRoute";
import BillsList from "../bill/BillsList";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import AppDrawer from "../drawer/AppDrawer";
import NoUserAppDrawer from "../drawer/NoUserAppDrawer";
import LegislatorRoute from "../legislator/LegislatorRoute";
import Legislators from "../legislator/Legislators";
import Home from "./Home";
import Invite from "./Invite";
import PasswordReset from "./PasswordReset";
import Registration from "./Registration";
import UserSettings from "./settings/UserSettings";
import SignIn from "./SignIn";
import SignUp from "./SignUp";
import UserInfluence from "./UserSwayInfluence";

const BillOfTheWeekCreator = lazy(() => import("../admin/BillOfTheWeekCreator"));
interface IProps {
    userWithSettingsAdmin: sway.IUserWithSettingsAdmin | undefined;
}

export interface ILocaleUserProps {
    user: sway.IUser | undefined;
}

const UserRouter: React.FC<IProps> = ({ userWithSettingsAdmin }) => {
    const user = userWithSettingsAdmin?.user;
    const isAdmin = Boolean(userWithSettingsAdmin?.isAdmin);

    logDev("Render UserRouter with user authed?", user && user.isRegistrationComplete);

    const renderWithDrawer = (Component: any) => {
        return (
            <WithDrawer user={user}>
                <Component user={user} userWithSettingsAdmin={userWithSettingsAdmin} />
            </WithDrawer>
        );
    };

    return (
        <BrowserRouter>
            <Routes>
                <Route path="/">
                    <Route index element={<Home user={user} />} />
                    <Route path={"signup"} element={<SignUp />} />

                    <Route path={"signin"} element={<SignIn />} />

                    <Route path={"passwordreset"} element={<PasswordReset />} />

                    <Route path={"registration"} element={<Registration />} />

                    <Route path="invite">
                        <Route path={":uid"} element={<Invite />} />
                    </Route>

                    <Route path={"*"}>
                        <Route index element={renderWithDrawer(Legislators)} />
                        <Route
                            path={"legislators/:localeName/:externalLegislatorId"}
                            element={renderWithDrawer(LegislatorRoute)}
                        />
                        <Route path={"legislators"} element={renderWithDrawer(Legislators)} />

                        <Route
                            path={"bill-of-the-week"}
                            element={renderWithDrawer(BillOfTheWeek)}
                        />

                        <Route
                            path={"bills/:localeName/:billFirestoreId"}
                            element={renderWithDrawer(BillRoute)}
                        />
                        <Route path={"bills"} element={renderWithDrawer(BillsList)} />

                        <Route path={"influence"} element={renderWithDrawer(UserInfluence)} />

                        <Route path={"settings"} element={renderWithDrawer(UserSettings)} />
                        {isAdmin && (
                            <Route path="admin">
                                <Route path="bills">
                                    <Route
                                        path="creator"
                                        element={
                                            <Suspense fallback={<FullScreenLoading />}>
                                                {renderWithDrawer(BillOfTheWeekCreator)}
                                            </Suspense>
                                        }
                                    />
                                </Route>
                            </Route>
                            // </Suspense>
                        )}
                    </Route>
                </Route>
            </Routes>
        </BrowserRouter>
    );
};

export default UserRouter;

const WithDrawer = (props: { user: sway.IUser | undefined; children: React.ReactNode }) => {
    const { user } = props;
    const Drawer = user && user.isRegistrationComplete ? AppDrawer : NoUserAppDrawer;

    return <Drawer user={user}>{props.children}</Drawer>;
};
