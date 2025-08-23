/** @format */

import { useUser } from "app/frontend/hooks/users/useUser";
import { ROUTES } from "app/frontend/sway_constants";
import { Fragment, createElement, useMemo } from "react";
import { FiBell, FiBookmark, FiClock, FiLogIn, FiLogOut, FiSearch, FiStar, FiTool, FiUsers } from "react-icons/fi";
import { SWAY_COLORS } from "../../sway_utils";
import SwayDrawer from "./SwayDrawer";
import InviteIconDialog from "app/frontend/components/dialogs/InviteIconDialog";
import { sway } from "sway";

type MenuItem = {
    route: string;
    Icon: React.FC<any>;
    text: string | React.ReactNode;
};
const MenuChoices: MenuItem[] = [
    { route: ROUTES.legislators, Icon: FiUsers, text: "Representatives" },
    { route: ROUTES.billOfTheWeek, Icon: FiBookmark, text: "Bill of the Week" },
    {
        route: ROUTES.pastBills,
        Icon: FiClock,
        text: "Past Bills of the Week",
    },
    {
        route: ROUTES.influence,
        Icon: FiStar,
        text: "Your Sway",
    },
];
const BOTTOM_MENU_CHOICES: MenuItem[] = [
    // { route: ROUTES.userSettings, Icon: Settings, text: "Settings" },
    {
        route: ROUTES.invite,
        Icon: (_user: sway.IUser) => createElement(InviteIconDialog, { withText: true }),
        text: "",
    },
    {
        route: ROUTES.notifications,
        Icon: FiBell,
        text: "Notifications",
    },
    { route: ROUTES.logout, Icon: FiLogOut, text: "Sign Out" },
];

const AdminChoices: MenuItem[] = [
    {
        route: ROUTES.billOfTheWeekCreator,
        Icon: FiTool,
        text: "Creator",
    },
];

interface IProps {
    children: React.ReactNode;
}

const SearchIcon = () => <FiSearch className="pulse-text" style={{ color: SWAY_COLORS.tertiaryLight }} />;
const Noop = () => <Fragment />;

const AppDrawer: React.FC<IProps> = (props) => {
    const user = useUser();

    const withFindRepresentativesPrepended = useMemo(() => {
        if (user?.is_registration_complete) return MenuChoices;

        return [
            {
                route: user ? ROUTES.registration : ROUTES.logout,
                Icon: user ? SearchIcon : FiLogIn,
                text: user ? "Find Representatives" : "Sign in to Sway",
            },
            {
                route: "divider",
                Icon: Noop,
                text: "",
            },
            ...MenuChoices,
        ];
    }, [user]);

    // If notifications are not supported, i.e. - "Notification" in window
    // do NOT show the notifications route as a choice.
    const bottomMenuChoices: MenuItem[] = useMemo(
        () =>
            (user?.is_admin ? BOTTOM_MENU_CHOICES.concat(AdminChoices) : BOTTOM_MENU_CHOICES).filter((choice) => {
                if (choice.route === ROUTES.logout && !user) {
                    return false;
                }
                if (choice.route !== ROUTES.notifications || "Notification" in window) {
                    return true;
                }
            }),
        [user],
    );

    return (
        <SwayDrawer menuChoices={withFindRepresentativesPrepended} bottomMenuChoices={bottomMenuChoices}>
            {props.children}
        </SwayDrawer>
    );
};

export default AppDrawer;
