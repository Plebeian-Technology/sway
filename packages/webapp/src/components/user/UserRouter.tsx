/** @format */

import Slide from "@material-ui/core/Slide";
import { ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import React from "react";
import {
    BrowserRouter as Router,
    Route,
    RouteComponentProps,
    Switch,
} from "react-router-dom";
import { sway } from "sway";
import Bill from "../bill/Bill";
import BillOfTheWeek from "../bill/BillOfTheWeek";
import BillsList from "../bill/BillsList";
import AppDrawer from "../drawer/AppDrawer";
import NoUserAppDrawer from "../drawer/NoUserAppDrawer";
import NoUserFab from "../fabs/NoUserFab";
import SwayFab from "../fabs/SwayFab";
import Legislator from "../legislator/Legislator";
import Legislators from "../legislator/Legislators";
import Home from "./Home";
import Invite from "./Invite";
import PasswordReset from "./PasswordReset";
import Registration from "./Registration";
import RegistrationIntroduction from "./RegistrationIntroduction";
import UserSettings from "./settings/UserSettings";
import SignIn from "./SignIn";
import SignUp from "./SignUp";
import UserInfluence from "./UserInfluence";

interface IProps {
    userWithSettings: sway.IUserWithSettings | undefined;
}

export interface ILocaleUserProps {
    user: sway.IUser | undefined;
}

const UserRouter: React.FC<IProps> = ({ userWithSettings }) => {
    const user = userWithSettings?.user;

    const Drawer =
        user && user.isRegistrationComplete ? AppDrawer : NoUserAppDrawer;

    logDev(
        "Render UserRouter with user authed?",
        user && user.isRegistrationComplete,
    );

    return (
        <>
            <Router>
                <Switch>
                    <Route path={ROUTES.index} exact={true}>
                        <Home user={user} />
                        {/* <SignIn /> */}
                        <SwayFab user={user} />
                    </Route>

                    <Route path={ROUTES.signup} exact={true}>
                        <SignUp />
                        <NoUserFab user={user} />
                    </Route>

                    <Route path={ROUTES.signin} exact={true}>
                        <SignIn />
                        <NoUserFab user={user} />
                    </Route>

                    <Route path={ROUTES.passwordreset} exact={true}>
                        <PasswordReset />
                        <NoUserFab user={user} />
                    </Route>

                    <Route path={ROUTES.registrationIntroduction} exact={true}>
                        <RegistrationIntroduction user={user} />
                    </Route>
                    <Route path={ROUTES.registration} exact={true}>
                        <Registration />
                    </Route>

                    <Route path={ROUTES.invite} component={Invite} />

                    <Drawer user={user}>
                        <Route path={ROUTES.legislators} exact={true}>
                            <Legislators user={user} />
                            {/* ) : (
                                <Redirect to={ROUTES.index} />
                            )} */}
                        </Route>
                        <Route path={ROUTES.billOfTheWeek} exact={true}>
                            <BillOfTheWeek user={user} />
                        </Route>
                        <Route path={ROUTES.pastBills} exact={true}>
                            <BillsList user={user} />
                        </Route>
                        <Route
                            path={ROUTES.bill()}
                            exact={true}
                            render={(routeProps: RouteComponentProps) => {
                                const locationState = routeProps?.location
                                    ?.state as {
                                    bill: sway.IBill;
                                    locale: sway.ILocale;
                                    organizations: sway.IOrganization[];
                                };
                                return (
                                    <Slide
                                        direction="left"
                                        in={true}
                                        mountOnEnter
                                        unmountOnExit
                                    >
                                        <div>
                                            <Bill
                                                user={user}
                                                {...locationState}
                                            />
                                        </div>
                                    </Slide>
                                );
                            }}
                        />
                        <Route
                            path={ROUTES.legislator}
                            exact={true}
                            render={(routeProps: RouteComponentProps) => {
                                return (
                                    <Slide
                                        direction="left"
                                        in={true}
                                        mountOnEnter
                                        unmountOnExit
                                    >
                                        <div>
                                            <Legislator
                                                user={user}
                                                {...routeProps}
                                            />
                                        </div>
                                    </Slide>
                                );
                            }}
                        />
                        <Route path={ROUTES.influence} exact={true}>
                            <UserInfluence user={userWithSettings?.user} />
                        </Route>
                        <Route path={ROUTES.userSettings} exact={true}>
                            <UserSettings userWithSettings={userWithSettings} />
                        </Route>
                    </Drawer>
                </Switch>
            </Router>
        </>
    );
};

export default UserRouter;
