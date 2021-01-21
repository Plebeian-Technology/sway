/** @format */

import { Typography } from "@material-ui/core";
import React from "react";
import { useDispatch } from "react-redux";
import { sway } from "sway";
import { setBillOfTheWeek } from "../../redux/actions/billActions";
import { handleError, legisFire, notify } from "../../utils";
import { removeTimestamps } from "@sway/utils"
import HtmlTooltip from "../HtmlTooltip";
import VoteButtons from "./VoteButtons";
import VoteConfirmationDialog from "./VoteConfirmationDialog";

interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale;
    bill: sway.IBill;
    organizations: sway.IOrganization[];
    userVote: sway.IUserVote | undefined;
    isLoadingUserVote: boolean;
}

interface IState {
    support: string | null;
    dialog: boolean;
    isSubmitting: boolean;
}

const VoteButtonsContainer: React.FC<IProps> = (props) => {
    const dispatch = useDispatch();
    const { locale } = props;

    const { bill, user, userVote } = props;

    const [state, setState] = React.useState<IState>({
        support: (userVote && userVote?.support) || null,
        dialog: false,
        isSubmitting: false,
    });

    const closeDialog = (support: string | null = null) => {
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

        const vote: sway.IUserVote | string | void = await legisFire(locale)
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

        const _newBill: sway.IBill | void = await legisFire(locale)
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
        const __newBill = removeTimestamps(_newBill);
        const score: sway.IBillScore = removeTimestamps(__newBill.score);
        const newBill: sway.IBill = {
            ...__newBill,
            score: score,
        };

        dispatch(
            setBillOfTheWeek({
                bill: newBill,
                organizations: props.organizations,
            }),
        );
        closeDialog(support);
        notify({
            level: "success",
            title: "Vote Saved",
            message: `Vote on bill ${bill.firestoreId} was saved successfully.`,
        });
    };

    const userIsRegistered = user?.uid && user?.isRegistrationComplete;
    const userButNotRegistered = user?.uid && !user?.isRegistrationComplete;
    const userSupport = state.support || userVote?.support || null;
    return (
        <div className={"vote-buttons-container"}>
            {userIsRegistered ? (
                <div className={"vote-buttons"}>
                    <VoteButtons
                        isLoadingUserVote={props.isLoadingUserVote}
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
                                {userButNotRegistered
                                    ? "Complete Your Registration to Vote!"
                                    : "Sign In to Vote!"}
                            </Typography>
                        </>
                    }
                >
                    <div className={"vote-buttons"}>
                        <VoteButtons
                            isLoadingUserVote={props.isLoadingUserVote}
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
        </div>
    );
};

export default VoteButtonsContainer;
