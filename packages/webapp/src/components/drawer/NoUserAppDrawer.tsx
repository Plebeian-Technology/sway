/** @format */

import { ROUTES } from "@sway/constants";

import { FiBookmark, FiClock, FiLogIn, FiUserPlus } from "react-icons/fi";

import { sway } from "sway";
import SwayDrawer from "./SwayDrawer";

type MenuItem = {
    route: string;
    Icon: React.FC<any>;
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
    user: sway.IUser | undefined;
    children: React.ReactNode;
}

const NoUserAppDrawer: React.FC<IProps> = (props) => {
    const needsToRegister = Boolean(props?.user?.isRegistrationComplete === false);

    const menuChoices: MenuItem[] = needsToRegister
        ? RegistrationChoice.concat(MenuChoices)
        : SignInChoice.concat(MenuChoices);

    return <SwayDrawer menuChoices={menuChoices} bottomMenuChoices={[]} {...props} />;
};

export default NoUserAppDrawer;
