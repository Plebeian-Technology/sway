/** @format */

import { useForm } from "@inertiajs/react";
import { Suspense, lazy, useCallback, useState } from "react";
import { ProgressBar } from "react-bootstrap";
import { sway } from "sway";
import { handleError, notify } from "../../sway_utils";
import VoteButtons from "./VoteButtons";
const VoteConfirmationDialog = lazy(() => import("./VoteConfirmationDialog"));

interface IProps {
    bill: sway.IBill;
    userVote?: sway.IUserVote | null;
}

const VoteButtonsContainer: React.FC<IProps> = ({ bill, userVote }) => {
    const [dialog, setDialog] = useState<boolean>(false);

    const {
        data,
        setData,
        post,
        processing,
        errors: _errors,
    } = useForm<{ bill_id: number } & Pick<sway.IUserVote, "support">>({
        bill_id: bill.id,
        support: userVote?.support,
    });

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
            });
            // .then(() => {
            //     closeDialog(verifiedSupport);
            //     notify({
            //         level: "success",
            //         title: `Vote on bill ${bill.externalId} cast!`,
            //         message: withTadas("You gained some Sway!"),
            //         tada: true,
            //     });
            //     setTimeout(() => {
            //         router.reload();
            //     }, 500);
            // })
            // .catch(console.error);
        },
        [post],
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
            <VoteButtons
                dialog={dialog}
                setDialog={setDialog}
                support={userVote?.support || data.support}
                setSupport={setSupport}
            />
            {(userVote?.support || data.support) && !!bill?.externalId && (
                <Suspense fallback={<ProgressBar animated now={100} />}>
                    <VoteConfirmationDialog
                        open={dialog}
                        isSubmitting={processing}
                        handleClose={handleVerifyVote}
                        support={(userVote?.support || data.support) as sway.TUserSupport}
                        bill={bill}
                    />
                </Suspense>
            )}
        </>
    );
};

export default VoteButtonsContainer;
