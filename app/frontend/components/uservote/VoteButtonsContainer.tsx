/** @format */

import { logDev } from "app/frontend/sway_utils";
import { useState } from "react";
import { sway } from "sway";
import { useLocale } from "../../hooks/useLocales";
import { useIsUserEmailVerified } from "../../hooks/users/useIsUserEmailVerified";
import { useIsUserRegistrationComplete } from "../../hooks/users/useIsUserRegistrationComplete";
import { useUserUid } from "../../hooks/users/useUserUid";
import { handleError, notify, withTadas } from "../../sway_utils";
import VoteButtons from "./VoteButtons";
import VoteConfirmationDialog from "./VoteConfirmationDialog";

interface IProps {
    bill: sway.IBill;
    updateBill?: () => void;
    userVote?: sway.IUserVote;
}

const VoteButtonsContainer: React.FC<IProps> = ({ bill, userVote, updateBill }) => {
    const [locale] = useLocale();
    const uid = useUserUid();
    const isEmailVerified = useIsUserEmailVerified();
    const isRegistrationComplete = useIsUserRegistrationComplete();
    const [support, setSupport] = useState<sway.TUserSupport | null>(
        (userVote?.support) || null,
    );
    const [dialog, setDialog] = useState<boolean>(false);
    const [isSubmitting, setSubmitting] = useState<boolean>(false);

    const closeDialog = (newSupport: sway.TUserSupport | null = null) => {
        setSupport(newSupport);
        setDialog(false);
    };

    const handleVerifyVote = (verified: boolean) => {
        if (isEmailVerified && verified && support) {
            createUserVote(support).catch(handleError);
        } else if (!isEmailVerified) {
            closeDialog();
            notify({
                level: "error",
                title: "Please verify your email address before voting!",
            });
        } else {
            closeDialog();
            notify({
                level: "error",
                title: `Vote on ${bill.externalId} was canceled.`,
            });
        }
    };

    const createUserVote = async (newSupport: sway.TUserSupport) => {
        if (!newSupport) return;
        if (!bill?.externalId) return;

        setSubmitting(true);
        if (!uid || !locale || !bill.externalId) return;

        // const vote: sway.IUserVote | string | void = await swayFireClient(locale)
        //     .userVotes(uid)
        //     .create(bill.externalId, newSupport);
        // if (!vote || typeof vote === "string") {
        //     logDev("create vote returned a non-string. received -", vote);
        //     notify({
        //         level: "error",
        //         title: vote || "No user vote",
        //     });
        //     closeDialog();
        //     return;
        // }

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
            updateBill && updateBill();
        }, 5000);

        closeDialog(support);
        notify({
            level: "success",
            title: `Vote on bill ${bill.externalId} cast!`,
            message: withTadas("You gained some Sway!"),
            tada: true,
        });
    };

    const userIsRegistered = uid && isRegistrationComplete;
    const userSupport = support || userVote?.support || null;
    return (
        <>
            <VoteButtons
                dialog={dialog}
                setDialog={setDialog}
                support={userSupport}
                setSupport={setSupport}
            />
            {!userIsRegistered && <h5>Sign In to Vote!</h5>}
            {userSupport && !!bill?.externalId && (
                <VoteConfirmationDialog
                    open={dialog}
                    isSubmitting={isSubmitting}
                    handleClose={handleVerifyVote}
                    support={userSupport}
                    bill={bill}
                />
            )}
        </>
    );
};

export default VoteButtonsContainer;
