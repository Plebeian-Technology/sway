/** @format */

import { SvgIconTypeMap } from "@material-ui/core";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import {
    AllInclusive,
    BuildRounded,
    ExitToApp,
    Gavel,
    People,
    Settings,
    Star,
} from "@material-ui/icons";
import { ROUTES } from "@sway/constants";
import { createElement } from "react";
import { sway } from "sway";
import { useAdmin } from "../../hooks";
import InviteIconDialog from "../dialogs/InviteIconDialog";
import SwayDrawer from "./SwayDrawer";

type MenuItem = {
    route: string;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
    text: string;
};
const AdminChoices: MenuItem[] = [
    {
        route: ROUTES.billOfTheWeekCreator,
        Icon: BuildRounded,
        text: "Creator",
    },
];
const MenuChoices: MenuItem[] = [
    { route: ROUTES.legislators, Icon: People, text: "Representatives" },
    { route: ROUTES.billOfTheWeek, Icon: Gavel, text: "Bill of the Week" },
    {
        route: ROUTES.pastBills,
        Icon: AllInclusive,
        text: "Past Bills of the Week",
    },
    {
        route: ROUTES.influence,
        Icon: Star,
        text: "Your Sway",
    },
];
const BottomMenuItems: MenuItem[] = [
    { route: ROUTES.userSettings, Icon: Settings, text: "Settings" }, // eslint-disable-next-line
    {
        route: "invite", // @ts-ignore
        Icon: (user: sway.IUser) => createElement(InviteIconDialog, user),
        text: "Invite Friends",
    },
    { route: ROUTES.logout, Icon: ExitToApp, text: "Sign Out" },
];

interface IProps {
    user: sway.IUser | undefined;
    children: React.ReactNode;
}

const AppDrawer: React.FC<IProps> = (props) => {
    const isAdmin = useAdmin();

    const menuChoices: MenuItem[] = isAdmin
        ? MenuChoices.concat(AdminChoices)
        : MenuChoices;

    return (
        <SwayDrawer
            menuChoices={menuChoices}
            bottomMenuChoices={BottomMenuItems}
            {...props}
        />
    );
};

export default AppDrawer;
