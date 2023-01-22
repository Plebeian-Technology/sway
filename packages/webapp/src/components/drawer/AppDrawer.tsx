/** @format */

import { ROUTES } from "@sway/constants";
import { createElement, Fragment } from "react";
import { FiBookmark, FiClock, FiLogOut, FiSearch, FiStar, FiTool, FiUsers } from "react-icons/fi";
import { sway } from "sway";
import { useAdmin } from "../../hooks";
import { SWAY_COLORS } from "../../utils";
import InviteIconDialog from "../dialogs/InviteIconDialog";
import SwayDrawer from "./SwayDrawer";

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
        route: "invite", // @ts-ignore
        Icon: (user: sway.IUser) => createElement(InviteIconDialog, { user, withText: true }),
        text: "",
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
    user: sway.IUser | undefined;
    children: React.ReactNode;
}

const AppDrawer: React.FC<IProps> = (props) => {
    const isAdmin = useAdmin();

    // const isFoundLegislators =
    //     props.user?.locales &&
    //     props.user?.locales.length > 1 &&
    //     props.user.locales.some((l) => !!l.district);

    const prependRegistration = (choices: MenuItem[]) => {
        // if (isFoundLegislators) return choices;

        return [
            {
                route: ROUTES.registration,
                Icon: () =>
                    createElement(FiSearch, {
                        className: "pulse-text",
                        style: { color: SWAY_COLORS.tertiaryLight },
                    }),
                text: <span className="pulse-text">Find Representatives</span>,
            },
            {
                route: "divider",
                Icon: () => createElement(Fragment),
                text: "",
            },
            ...choices,
        ];
    };

    const bottomMenuChoices: MenuItem[] = isAdmin
        ? BOTTOM_MENU_CHOICES.concat(AdminChoices)
        : BOTTOM_MENU_CHOICES;

    return (
        <SwayDrawer
            menuChoices={prependRegistration(MenuChoices)}
            bottomMenuChoices={bottomMenuChoices}
            {...props}
        />
    );
};

export default AppDrawer;
