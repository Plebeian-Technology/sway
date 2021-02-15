/** @format */

import { Typography } from "@material-ui/core";
import React from "react";
import { sway } from "sway";
import { handleError, notify, swayFireClient } from "../../utils";
import NewUserVoteAward from "../dialogs/awards/NewUserVoteAward";
import HtmlTooltip from "../HtmlTooltip";
import VoteButtons from "./VoteButtons";
import VoteConfirmationDialog from "./VoteConfirmationDialog";

interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale;
    bill: sway.IBill;
    updateBill?: () => void;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote | undefined;
}

interface IState {
    support: string | null;
    dialog: boolean;
    isSubmitting: boolean;
    isCongratulations: boolean;
}

const VoteButtonsContainer: React.FC<IProps> = (props) => {
    const { locale } = props;

    const { bill, user, userVote } = props;

    const [state, setState] = React.useState<IState>({
        support: (userVote && userVote?.support) || null,
        dialog: false,
        isSubmitting: false,
        isCongratulations: false,
    });

    const closeDialog = (
        support: string | null = null,
        isCongratulations = false,
    ) => {
        setState((prevState: IState) => ({
            ...prevState,
            support,
            dialog: false,
            isSubmitting: false,
            isCongratulations,
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
            message: `Vote on ${bill.firestoreId} was NOT saved.`,
            title: "Vote Cancelled",
            duration: 3000,
        });
    };

    const createUserVote = async (support: string) => {
        if (!bill || !bill.firestoreId) return;
        setState((prevState: IState) => ({
            ...prevState,
            isSubmitting: true,
        }));
        const uid = user?.uid;
        if (!uid || !locale || !bill.firestoreId) return;

        const vote: sway.IUserVote | string | void = await swayFireClient(
            locale,
        )
            .userVotes(uid)
            .create(bill.firestoreId, support);
        if (!vote || typeof vote === "string") {
            notify({
                level: "error",
                message: vote || "no user vote",
                title: "Error",
            });
            closeDialog();
            return;
        }

        const _newBill: sway.IBill | void = await swayFireClient(locale)
            .bills()
            .get(bill.firestoreId);
        if (!_newBill) {
            notify({
                level: "error",
                message: "no bill for user vote",
                title: "Error",
            });
            closeDialog();
            return;
        }

        props.updateBill && props.updateBill();
        closeDialog(support, true);
        notify({
            level: "success",
            title: "Vote Saved",
            message: `Vote on bill ${bill.firestoreId} was saved successfully.`,
        });
    };

    const userIsRegistered = user?.uid && user?.isRegistrationComplete;
    const userSupport = state.support || userVote?.support || null;
    return (
        <div className={"vote-buttons-container"}>
            {userIsRegistered ? (
                <div className={"vote-buttons"}>
                    <VoteButtons
                        dialog={state.dialog}
                        user={user}
                        setState={setState}
                        support={userSupport}
                    />
                </div>
            ) : (
                <HtmlTooltip
                    placement={"top"}
                    title={
                        <>
                            <Typography component={"h5"} variant={"h5"}>
                                Sign In to Vote!
                            </Typography>
                        </>
                    }
                >
                    <div className={"vote-buttons"}>
                        <VoteButtons
                            dialog={state.dialog}
                            user={user}
                            setState={setState}
                            support={userSupport}
                        />
                    </div>
                </HtmlTooltip>
            )}
            {userSupport && !!bill.firestoreId && (
                <VoteConfirmationDialog
                    open={state.dialog}
                    isSubmitting={state.isSubmitting}
                    handleClose={handleVerifyVote}
                    support={userSupport}
                    billFirestoreId={bill.firestoreId}
                />
            )}
            {user && state.isCongratulations && (
                <NewUserVoteAward user={user} locale={locale} />
            )}
        </div>
    );
};

export default VoteButtonsContainer;
