/** @format */

import { Typography } from "@material-ui/core";
import { useState } from "react";
import { sway } from "sway";
import { useUserSettings } from "../../hooks";
import { useCongratulations } from "../../hooks/awards";
import {
    AWARD_TYPES,
    handleError,
    notify,
    swayFireClient,
    SWAY_COLORS,
} from "../../utils";
import Award from "../user/awards/Award";
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
    const settings = useUserSettings();

    const { bill, user, userVote } = props;
    const [isCongratulations, setIsCongratulations] = useCongratulations();
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
            message: `Vote on ${bill.firestoreId} was NOT saved.`,
            title: "Vote Cancelled",
            duration: 3000,
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
        closeDialog(support);
        setIsCongratulations(
            settings?.congratulations?.isCongratulateOnUserVote === undefined
                ? true
                : settings?.congratulations?.isCongratulateOnUserVote,
        );
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
            {user && isCongratulations && (
                <Award
                    user={user}
                    locale={locale}
                    type={AWARD_TYPES.Vote}
                    setIsCongratulations={setIsCongratulations}
                />
            )}
        </div>
    );
};

export default VoteButtonsContainer;
