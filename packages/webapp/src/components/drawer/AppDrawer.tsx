/** @format */

import {
    AllInclusive,
    ExitToApp,
    Gavel,
    HowToReg,
    People,
    Settings,
    Star,
} from "@material-ui/icons";
import { ROUTES } from "@sway/constants";
import { createElement, Fragment } from "react";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import InviteIconDialog from "../dialogs/InviteIconDialog";
import { TSwaySvg } from "../SwaySvg";
import SwayDrawer from "./SwayDrawer";

type MenuItem = {
    route: string;
    Icon: TSwaySvg;
    text: string | React.ReactNode;
};
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
    { route: ROUTES.userSettings, Icon: Settings, text: "Settings" },
    {
        // eslint-disable-next-line
        route: "invite", // @ts-ignore
        Icon: (user: sway.IUser) => createElement(InviteIconDialog, user),
        text: "",
    },
    { route: ROUTES.logout, Icon: ExitToApp, text: "Sign Out" },
];

interface IProps {
    user: sway.IUser | undefined;
    children: React.ReactNode;
}

const AppDrawer: React.FC<IProps> = (props) => {
    const isFindLegislators =
        props.user?.locales && props.user?.locales.length > 1;

    const prependRegistration = (choices: MenuItem[]) => {
        if (isFindLegislators) return choices;

        return [
            {
                route: ROUTES.registration,
                Icon: () =>
                    createElement(HowToReg, {
                        className: "pulse-text",
                        style: { color: SWAY_COLORS.tertiaryLight },
                    }),
                text: <span className="pulse-text">Find Legislators</span>,
            },
            {
                route: "",
                Icon: () => createElement(Fragment),
                text: "",
            },
            ...choices,
        ];
    };

    return (
        <SwayDrawer
            menuChoices={prependRegistration(MenuChoices)}
            bottomMenuChoices={BottomMenuItems}
            {...props}
        />
    );
};

export default AppDrawer;
