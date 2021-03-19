/** @format */

import { Typography } from "@material-ui/core";
import { useState } from "react";
import { sway } from "sway";
import {
    GAINED_SWAY_MESSAGE,
    handleError,
    notify,
    swayFireClient,
    SWAY_COLORS,
    withTadas
} from "../../utils";
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
    support: "for" | "against" | null;
    dialog: boolean;
    isSubmitting: boolean;
}

const VoteButtonsContainer: React.FC<IProps> = (props) => {
    const { locale } = props;

    const { bill, user, userVote } = props;
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
            message: `Vote on ${bill.firestoreId} was canceled.`,
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

        const vote: sway.IUserVote | string | void = await swayFireClient(
            locale,
        )
            .userVotes(uid)
            .create(bill.firestoreId, support);
        if (!vote || typeof vote === "string") {
            notify({
                level: "error",
                message: vote || "No user vote",
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
                message: "No bill for user vote",
            });
            closeDialog();
            return;
        }

        props.updateBill && props.updateBill();
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
        <div className={"vote-buttons-container"}>
            <div className={"vote-buttons"}>
                <VoteButtons
                    dialog={state.dialog}
                    user={user}
                    setState={setState}
                    support={userSupport}
                />
                {!userIsRegistered && (
                    <Typography
                        component={"h5"}
                        variant={"h5"}
                        style={{
                            color: SWAY_COLORS.primary,
                            fontWeight: 900,
                            marginBottom: 20,
                        }}
                    >
                        Sign In to Vote!
                    </Typography>
                )}
            </div>
            {userSupport && !!bill?.firestoreId && (
                <VoteConfirmationDialog
                    open={state.dialog}
                    isSubmitting={state.isSubmitting}
                    handleClose={handleVerifyVote}
                    support={userSupport}
                    billFirestoreId={bill?.firestoreId}
                />
            )}
        </div>
    );
};

export default VoteButtonsContainer;
