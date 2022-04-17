/** @format */

import { logDev } from "@sway/utils";
import { useState } from "react";
import { sway } from "sway";
import { GAINED_SWAY_MESSAGE, handleError, notify, swayFireClient, withTadas } from "../../utils";
import VoteButtons from "./VoteButtons";
import VoteConfirmationDialog from "./VoteConfirmationDialog";

interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale;
    bill: sway.IBill;
    updateBill?: () => void;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote;
}

interface IState {
    support: "for" | "against" | null;
    dialog: boolean;
    isSubmitting: boolean;
}

const VoteButtonsContainer: React.FC<IProps> = (props) => {
    const { bill, locale, user, userVote } = props;
    const [state, setState] = useState<IState>({
        support: (userVote && userVote?.support) || null,
        dialog: false,
        isSubmitting: false,
    });

    const closeDialog = (support: "for" | "against" | null = null) => {
        setState((prevState: IState) => ({
            ...prevState,
            support,
            dialog: false,
            isSubmitting: false,
        }));
    };

    const handleVerifyVote = (verified: boolean) => {
        if (verified && state.support) {
            createUserVote(state.support).catch(handleError);
            return;
        }
        closeDialog();
        notify({
            level: "error",
            title: `Vote on ${bill.firestoreId} was canceled.`,
        });
    };

    const createUserVote = async (support: "for" | "against") => {
        if (!bill || !bill.firestoreId) return;
        setState((prevState: IState) => ({
            ...prevState,
            isSubmitting: true,
        }));
        const uid = user?.uid;
        if (!uid || !locale || !bill.firestoreId) return;

        const vote: sway.IUserVote | string | void = await swayFireClient(locale)
            .userVotes(uid)
            .create(bill.firestoreId, support);
        if (!vote || typeof vote === "string") {
            logDev("create vote returned a non-string. received -", vote);
            notify({
                level: "error",
                title: vote || "No user vote",
            });
            closeDialog();
            return;
        }

        setTimeout(() => {
            // TODO: COME UP WITH SOMETHING BETTER THAN THIS
            // TODO: RACE CONDITION WITH ON_INSERT_USER_VOTE_UPDATE_SCORE
            logDev("************************************************");
            logDev("");
            logDev("COME UP WITH SOMETHING BETTER THAN THIS");
            logDev("COME UP WITH SOMETHING BETTER THAN THIS");
            logDev("COME UP WITH SOMETHING BETTER THAN THIS");
            logDev("");
            logDev("************************************************");
            props.updateBill && props.updateBill();
        }, 5000);

        closeDialog(support);
        notify({
            level: "success",
            title: `Vote on bill ${bill.firestoreId} was saved successfully.`,
            message: withTadas(GAINED_SWAY_MESSAGE),
            tada: true,
        });
    };

    const userIsRegistered = user?.uid && user?.isRegistrationComplete;
    const userSupport = state.support || userVote?.support || null;
    return (
        <>
            <VoteButtons
                dialog={state.dialog}
                user={user}
                setState={setState}
                support={userSupport}
            />
            {!userIsRegistered && <h5>Sign In to Vote!</h5>}
            {userSupport && !!bill?.firestoreId && (
                <VoteConfirmationDialog
                    open={state.dialog}
                    isSubmitting={state.isSubmitting}
                    handleClose={handleVerifyVote}
                    support={userSupport}
                    bill={bill}
                />
            )}
        </>
    );
};

export default VoteButtonsContainer;
