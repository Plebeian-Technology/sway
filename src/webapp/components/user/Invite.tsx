/** @format */

import { SWAY_REDEEMING_INVITE_FROM_UID_COOKIE } from "src/constants";
import { logDev, setStorage } from "src/utils";
import { useCallback, useEffect } from "react";
import { useDispatch } from "react-redux";
import { useLocation } from "react-router-dom";

import { useInviteUid } from "../../hooks";
import { setInviteUid } from "../../redux/actions/userActions";
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
        setStorage(SWAY_REDEEMING_INVITE_FROM_UID_COOKIE, inviterUrlUid);
        dispatchUid(inviterUrlUid);
    }, [inviterUrlUid, inviterReduxUid, dispatchUid]);

    if (!inviterReduxUid) {
        return <FullScreenLoading />;
    }

    return <SignIn />;
};
export default Invite;