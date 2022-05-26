/** @format */

import { SwayStorage } from "@sway/constants";
import { logDev } from "@sway/utils";
import { useCallback, useEffect } from "react";
import { useDispatch } from "react-redux";
import { useLocation } from "react-router-dom";

import { useInviteUid } from "../../hooks";
import { setInviteUid } from "../../redux/actions/userActions";
import { localSet } from "../../utils";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SignIn from "./SignIn";

const Invite: React.FC = () => {
    const dispatch = useDispatch();
    const inviterReduxUid = useInviteUid();
    const inviterUrlUids = (useLocation().pathname || "").split("/");
    const inviterUrlUid = inviterUrlUids[inviterUrlUids.length - 1];

    logDev("handling new user redeeming invite, sender uid -", inviterUrlUid);

    const dispatchUid = useCallback(
        (_uid: string) => {
            dispatch(setInviteUid(_uid));
        },
        [dispatch],
    );

    useEffect(() => {
        if (inviterReduxUid) return;
        localSet(SwayStorage.Local.User.InvitedBy, inviterUrlUid);
        dispatchUid(inviterUrlUid);
    }, [inviterUrlUid, inviterReduxUid, dispatchUid]);

    if (!inviterReduxUid) {
        return <FullScreenLoading />;
    }

    return <SignIn />;
};
export default Invite;
