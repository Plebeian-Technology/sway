/** @format */

import { useCallback, useEffect } from "react";
import { useDispatch } from "react-redux";
import { RouteChildrenProps } from "react-router-dom";
import { useInviteUid } from "../../hooks";
import { setInviteUid } from "../../redux/actions/userActions";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import SignIn from "./SignIn";

const Invite: React.FC<RouteChildrenProps> = ({ location }) => {
    const dispatch = useDispatch();
    const inviteUid = useInviteUid();
    const uids = location.pathname.split("/");
    const uid = uids[uids.length - 1];

    const dispatchUid = useCallback(
        (_uid: string) => {
            dispatch(setInviteUid(_uid));
        },
        [dispatch]
    );

    useEffect(() => {
        if (inviteUid) return;

        dispatchUid(uid);
    }, [uid, inviteUid, dispatchUid]);

    if (!inviteUid) {
        return <FullScreenLoading />;
    }

    return <SignIn />;
};
export default Invite;
