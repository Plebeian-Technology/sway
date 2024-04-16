/** @format */

import { lazy, PropsWithChildren, Suspense, useCallback } from "react";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import { sway } from "sway";
import { useIsUserRegistrationComplete } from "../../hooks/users/useIsUserRegistrationComplete";
import { useAdmin } from "../../hooks/users/useUserAdmin";
const BillOfTheWeek = lazy(() => import("../bill/BillOfTheWeek"));
const BillRoute = lazy(() => import("../bill/BillRoute"));
const BillsList = lazy(() => import("../bill/BillsList"));
import CenteredLoading from "../dialogs/CenteredLoading";
import FullScreenLoading from "../dialogs/FullScreenLoading";
const AppDrawer = lazy(() => import("../drawer/AppDrawer"));
const NoUserAppDrawer = lazy(() => import("../drawer/NoUserAppDrawer"));
const LegislatorRoute = lazy(() => import("../legislator/LegislatorRoute"));
const Legislators = lazy(() => import("../legislator/Legislators"));
const Invite = lazy(() => import("./Invite"));
const UserSettings = lazy(() => import("./settings/UserSettings"));
import Home from "./Home";
import PasswordReset from "./PasswordReset";
import SignIn from "./SignIn";
import SignUp from "./SignUp";
const UserSwayInfluence = lazy(() => import("./UserSwayInfluence"));

const Registration = lazy(() => import("./Registration"));
const BillOfTheWeekCreator = lazy(() => import("../admin/BillOfTheWeekCreator"));

export interface ILocaleUserProps {
    user: sway.IUser | undefined;
}

const UserRouter: React.FC = () => {
    const isAdmin = useAdmin();

    const renderWithDrawer = useCallback((Component: React.FC<any>) => {
        return (
            <Suspense fallback={<CenteredLoading message="Loading..." />}>
                <WithDrawer>
                    <Component />
                </WithDrawer>
            </Suspense>
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
                        <Route
                            path={":uid"}
                            element={
                                <Suspense fallback={<CenteredLoading message="Loading..." />}>
                                    <Invite />
                                </Suspense>
                            }
                        />
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

                        <Route path={"influence"} element={renderWithDrawer(UserSwayInfluence)} />

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
