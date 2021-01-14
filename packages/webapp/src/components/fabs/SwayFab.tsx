/** @format */

import { sway } from "sway";
import React from "react";
import SupportFab from "./SupportFab";
import NoUserFab from "./NoUserFab";

interface IProps {
    user: sway.IUser | undefined;
}

const SwayFab: React.FC<IProps> = ({ user }) => {
    const needsToRegister = Boolean(user && !user.isRegistrationComplete);

    const FabComponent = !user || needsToRegister ? NoUserFab : SupportFab;

    return <FabComponent user={user} />;
};

export default SwayFab;
