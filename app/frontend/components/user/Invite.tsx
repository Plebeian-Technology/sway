/** @format */

import { logDev } from "app/frontend/sway_utils";
import { useCallback, useEffect } from "react";
import { useDispatch } from "react-redux";
import { useUserInviteUuid } from "../../hooks/users/useUserInviteUuid";
import { setInviteUid } from "../../redux/actions/userActions";
import { localSet, SWAY_STORAGE } from "../../sway_utils";
import FullScreenLoading from "../dialogs/FullScreenLoading";

const Invite: React.FC = () => {
    const dispatch = useDispatch();
    const inviterReduxUid = useUserInviteUuid();
    const inviterUrlUids = (window.location.pathname || "").split("/");
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
        localSet(SWAY_STORAGE.Local.User.InvitedBy, inviterUrlUid);
        dispatchUid(inviterUrlUid);
    }, [inviterUrlUid, inviterReduxUid, dispatchUid]);

    if (!inviterReduxUid) {
        return <FullScreenLoading />;
    }
    return null;
};
export default Invite;
