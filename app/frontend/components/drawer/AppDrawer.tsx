/** @format */

import { useUser } from "app/frontend/hooks/users/useUser";
import { ROUTES } from "app/frontend/sway_constants";
import { Fragment, createElement, useMemo } from "react";
import { FiBell, FiBookmark, FiClock, FiLogOut, FiSearch, FiStar, FiTool, FiUsers } from "react-icons/fi";
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

const AppDrawer: React.FC<IProps> = (props) => {
    const user = useUser();

    const withFindRepresentativesPrepended = useMemo(() => {
        if (user?.isRegistrationComplete) return MenuChoices;

        return [
            {
                route: ROUTES.registration,
                Icon: () => <FiSearch className="pulse-text" style={{ color: SWAY_COLORS.tertiaryLight }} />,
                text: <span className="pulse-text">Find Representatives</span>,
            },
            {
                route: "divider",
                Icon: () => <Fragment />,
                text: "",
            },
            ...MenuChoices,
        ];
    }, [user?.isRegistrationComplete]);

    const bottomMenuChoices: MenuItem[] = useMemo(
        () => (user?.isAdmin ? BOTTOM_MENU_CHOICES.concat(AdminChoices) : BOTTOM_MENU_CHOICES),
        [user?.isAdmin],
    );

    return (
        <SwayDrawer
            menuChoices={withFindRepresentativesPrepended}
            bottomMenuChoices={bottomMenuChoices}
        >
            {props.children}
        </SwayDrawer>
    );
};

export default AppDrawer;
