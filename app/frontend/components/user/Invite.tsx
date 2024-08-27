/** @format */

import { logDev } from "app/frontend/sway_utils";

const Invite: React.FC = () => {
    // const inviterReduxUid = useUserInviteUuid();
    const inviterUrlUids = (window.location.pathname || "").split("/");
    const inviterUrlUid = inviterUrlUids[inviterUrlUids.length - 1];

    logDev("handling new user redeeming invite, sender uid -", inviterUrlUid);

    // const dispatchUid = useCallback(
    //     (_uid: string) => {
    //         dispatch(setInviteUid(_uid));
    //     },
    //     [dispatch],
    // );

    // useEffect(() => {
    //     if (inviterReduxUid) return;
    //     localSet(SWAY_STORAGE.Local.User.InvitedBy, inviterUrlUid);
    //     dispatchUid(inviterUrlUid);
    // }, [inviterUrlUid, inviterReduxUid, dispatchUid]);

    // if (!inviterReduxUid) {
    //     return <FullScreenLoading />;
    // }
    return null;
};
export default Invite;
