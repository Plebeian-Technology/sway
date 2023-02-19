/** @format */

import { lazy, PropsWithChildren, Suspense, useCallback } from "react";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import { sway } from "sway";
import { useIsUserRegistrationComplete } from "../../hooks/users/useIsUserRegistrationComplete";
import { useAdmin } from "../../hooks/users/useUserAdmin";
import BillOfTheWeek from "../bill/BillOfTheWeek";
import BillRoute from "../bill/BillRoute";
import BillsList from "../bill/BillsList";
import CenteredLoading from "../dialogs/CenteredLoading";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import AppDrawer from "../drawer/AppDrawer";
import NoUserAppDrawer from "../drawer/NoUserAppDrawer";
import LegislatorRoute from "../legislator/LegislatorRoute";
import Legislators from "../legislator/Legislators";
import Home from "./Home";
import Invite from "./Invite";
import PasswordReset from "./PasswordReset";
import UserSettings from "./settings/UserSettings";
import SignIn from "./SignIn";
import SignUp from "./SignUp";
import UserInfluence from "./UserSwayInfluence";

const Registration = lazy(() => import("./Registration"));
const BillOfTheWeekCreator = lazy(() => import("../admin/BillOfTheWeekCreator"));

export interface ILocaleUserProps {
    user: sway.IUser | undefined;
}

const UserRouter: React.FC = () => {
    const isAdmin = useAdmin();

    const renderWithDrawer = useCallback((Component: React.FC<any>) => {
        return (
            <WithDrawer>
                <Component />
            </WithDrawer>
        );
    }, []);

    return (
        <BrowserRouter>
            <Routes>
                <Route path="/">
                    <Route index element={<Home />} />
                    <Route path={"signup"} element={<SignUp />} />

                    <Route path={"signin"} element={<SignIn />} />

                    <Route path={"passwordreset"} element={<PasswordReset />} />

                    <Route
                        path={"registration"}
                        element={
                            <Suspense
                                fallback={<CenteredLoading message="Loading Registration..." />}
                            >
                                <Registration />
                            </Suspense>
                        }
                    />

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

const WithDrawer: React.FC<PropsWithChildren> = ({ children }) => {
    const isRegistrationComplete = useIsUserRegistrationComplete();
    const Drawer = isRegistrationComplete ? AppDrawer : NoUserAppDrawer;
    return <Drawer>{children}</Drawer>;
};
