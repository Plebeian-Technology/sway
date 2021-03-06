/** @format */

import { SvgIconTypeMap } from "@material-ui/core";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import { AllInclusive, Gavel, HowToReg, Navigation } from "@material-ui/icons";
import { ROUTES } from "@sway/constants";
import React from "react";
import { sway } from "sway";
import SwayDrawer from "./SwayDrawer";

type MenuItem = {
    route: string;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
    text: string;
};
const MenuChoices: MenuItem[] = [
    { route: ROUTES.billOfTheWeek, Icon: Gavel, text: "Bill of the Week" },
    {
        route: ROUTES.pastBills,
        Icon: AllInclusive,
        text: "Past Bills of the Week",
    },
];
const SignInChoice: MenuItem[] = [
    { route: ROUTES.signin, Icon: Navigation, text: "Sign In" },
];
const RegistrationChoice: MenuItem[] = [
    {
        route: ROUTES.registrationIntroduction,
        Icon: HowToReg,
        text: "Registration",
    },
];

interface IProps {
    user: sway.IUser | undefined;
    children: React.ReactNode;
}

const NoUserAppDrawer: React.FC<IProps> = (props) => {
    const needsToRegister = Boolean(
        props?.user?.isRegistrationComplete === false,
    );

    const menuChoices: MenuItem[] = needsToRegister
        ? RegistrationChoice.concat(MenuChoices)
        : SignInChoice.concat(MenuChoices);

    return (
        <SwayDrawer
            menuChoices={menuChoices}
            bottomMenuChoices={[]}
            {...props}
        />
    );
};

export default NoUserAppDrawer;
