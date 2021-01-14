/** @format */

import Slide from "@material-ui/core/Slide";
import { ROUTES } from "@sway/constants";
import React from "react";
import {
    BrowserRouter as Router,
    Redirect,
    Route,
    RouteComponentProps,
    Switch,
} from "react-router-dom";
import { sway } from "sway";
import Bill from "../bill/Bill";
import BillOfTheWeek from "../bill/BillOfTheWeek";
import BillOfTheWeekCreator from "../bill/BillOfTheWeekCreator";
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
import SignIn from "./SignIn";
import SignUp from "./SignUp";
import UserSettings from "./UserSettings";

interface IProps {
    locale: sway.ILocale;
    userWithSettingsAdmin: sway.IUserWithSettingsAdmin | undefined;
}

export interface ILocaleUserProps {
    locale: sway.ILocale;
    user: sway.IUser | undefined;
}

const UserRouter: React.FC<IProps> = ({ userWithSettingsAdmin, locale }) => {
    const isAdmin = Boolean(userWithSettingsAdmin?.isAdmin);
    const user = userWithSettingsAdmin?.user;

    const Drawer =
        user && user.isRegistrationComplete ? AppDrawer : NoUserAppDrawer;

    const withTitle = (
        routeProps: RouteComponentProps,
        Component: React.FC,
        title: string,
        props = {},
    ) => {
        const state: sway.IPlainObject = (routeProps?.location?.state ||
            {}) as sway.IPlainObject;
        routeProps.location.state = {
            ...state,
            title: title,
        };
        return <Component {...props} />;
    };

    return (
        <>
            <Router>
                <Switch>
                    <Route path={ROUTES.index} exact={true}>
                        <Home user={user} locale={locale} />
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

                    <Drawer locale={locale} user={user}>
                        <Route path={ROUTES.legislators} exact={true}>
                            {locale.name ? (
                                <Legislators locale={locale} user={user} />
                            ) : (
                                <Redirect to={ROUTES.index} />
                            )}
                        </Route>
                        <Route path={ROUTES.billOfTheWeek} exact={true}>
                            <BillOfTheWeek locale={locale} user={user} />
                        </Route>
                        <Route path={ROUTES.pastBills} exact={true}>
                            <BillsList locale={locale} user={user} />
                        </Route>
                        <Route
                            path={ROUTES.bill}
                            exact={true}
                            render={(routeProps: RouteComponentProps) => {
                                const locationState = routeProps?.location?.state as {
                                    bill: sway.IBill;
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
                                                locale={locale}
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
                            render={() => {
                                return (
                                    <Slide
                                        direction="left"
                                        in={true}
                                        mountOnEnter
                                        unmountOnExit
                                    >
                                        <div>
                                            <Legislator
                                                locale={locale}
                                                user={user}
                                            />
                                        </div>
                                    </Slide>
                                );
                            }}
                        />
                        {isAdmin && (
                            <Route
                                path={ROUTES.billOfTheWeekCreator}
                                exact={true}
                                render={(routeProps: RouteComponentProps) =>
                                    withTitle(
                                        routeProps,
                                        BillOfTheWeekCreator,
                                        "Bill of the Week Creator",
                                    )
                                }
                            />
                        )}
                        <Route path={ROUTES.userSettings} exact={true}>
                            <UserSettings
                                userWithSettingsAdmin={userWithSettingsAdmin}
                            />
                        </Route>
                    </Drawer>
                </Switch>
            </Router>
        </>
    );
};

export default UserRouter;
