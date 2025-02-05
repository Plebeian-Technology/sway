/** @format */

import { useForm } from "@inertiajs/react";
import { lazy, Suspense, useCallback, useMemo, useState } from "react";
import { sway } from "sway";
import { handleError, logDev, notify, withTadas } from "../../sway_utils";
import VoteButtons from "./VoteButtons";
const VoteConfirmationDialog = lazy(() => import("./VoteConfirmationDialog"));

interface IProps {
    bill: sway.IBill;
    userVote?: sway.IUserVote | null;
}

const VoteButtonsContainer: React.FC<IProps> = ({ bill, userVote }) => {
    const [dialog, setDialog] = useState<boolean>(false);

    logDev("userVote", userVote);
    const defaultValues = useMemo(
        () => ({
            bill_id: bill.id,
            support: userVote?.support,
            redirect_to: window.location.pathname,
        }),
        [bill.id, userVote?.support],
    );

    const {
        data,
        setData,
        post,
        processing,
        errors: _errors,
    } = useForm<{ bill_id: number; redirect_to: string } & Pick<sway.IUserVote, "support">>(defaultValues);

    const setSupport = useCallback(
        (newSupport: sway.TUserSupport | undefined) => setData("support", newSupport),
        [setData],
    );

    const closeDialog = useCallback(
        (newSupport?: sway.TUserSupport) => {
            setSupport(newSupport);
            setDialog(false);
        },
        [setSupport],
    );

    const createUserVote = useCallback(
        async (verifiedSupport: sway.TUserSupport) => {
            if (!verifiedSupport) return;

            post("/user_votes", {
                preserveScroll: true,
                onFinish: () => {
                    closeDialog(verifiedSupport);
                },
                onSuccess: () => {
                    notify({
                        level: "success",
                        title: `Vote on bill ${bill.externalId} cast!`,
                        message: withTadas("You gained some Sway!"),
                    });
                },
                onError: () => {
                    notify({
                        level: "error",
                        title: "Error saving vote.",
                        message: "Please try again.",
                    });
                },
            });
        },
        [bill.externalId, closeDialog, post],
    );

    const handleVerifyVote = useCallback(
        (verified: boolean) => {
            if (verified && data.support) {
                createUserVote(data.support).catch(handleError);
            } else {
                closeDialog();
                notify({
                    level: "error",
                    title: `Vote on ${bill.externalId} was canceled.`,
                });
            }
        },
        [bill.externalId, closeDialog, createUserVote, data.support],
    );

    return (
        <>
            <VoteButtons dialog={dialog} setDialog={setDialog} support={data.support} setSupport={setSupport} />
            {data.support && !!bill?.externalId && (
                <Suspense fallback={null}>
                    <VoteConfirmationDialog
                        open={dialog}
                        isSubmitting={processing}
                        handleClose={handleVerifyVote}
                        support={data.support as sway.TUserSupport}
                        bill={bill}
                    />
                </Suspense>
            )}
        </>
    );
};

export default VoteButtonsContainer;
