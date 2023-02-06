/** @format */

import { ROUTES } from "@sway/constants";
import { useMemo } from "react";
import { IconBaseProps } from "react-icons";

import { FiBookmark, FiClock, FiLogIn, FiLogOut, FiUserPlus } from "react-icons/fi";

import { useIsUserRegistrationComplete } from "../../hooks";
import SwayDrawer from "./SwayDrawer";

type MenuItem = {
    route: string;
    Icon: React.FC<IconBaseProps>;
    text: string;
};
const MenuChoices: MenuItem[] = [
    { route: ROUTES.billOfTheWeek, Icon: FiBookmark, text: "Bill of the Week" },
    {
        route: ROUTES.pastBills,
        Icon: FiClock,
        text: "Past Bills of the Week",
    },
];
const SignInChoice: MenuItem[] = [{ route: ROUTES.signin, Icon: FiLogIn, text: "Sign In" }];
const RegistrationChoice: MenuItem[] = [
    {
        route: ROUTES.registration,
        Icon: FiUserPlus,
        text: "Registration",
    },
];

interface IProps {
    children: React.ReactNode;
}

const BOTTOM_MENU_CHOICES = [
    { route: ROUTES.logout, Icon: FiLogOut, text: "Sign Out" },
] as MenuItem[];

const NoUserAppDrawer: React.FC<IProps> = (props) => {
    const isRegistrationComplete = useIsUserRegistrationComplete();

    const menuChoices: MenuItem[] = useMemo(
        () =>
            isRegistrationComplete === false
                ? RegistrationChoice.concat(MenuChoices)
                : SignInChoice.concat(MenuChoices),
        [isRegistrationComplete],
    );

    return (
        <SwayDrawer menuChoices={menuChoices} bottomMenuChoices={BOTTOM_MENU_CHOICES}>
            {props.children}
        </SwayDrawer>
    );
};

export default NoUserAppDrawer;
