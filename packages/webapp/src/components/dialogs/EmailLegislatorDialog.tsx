/** @format */
import { MenuItem, TextField } from "@material-ui/core";
import Button from "@material-ui/core/Button";
import Dialog from "@material-ui/core/Dialog";
import DialogContent from "@material-ui/core/DialogContent";
import DialogTitle from "@material-ui/core/DialogTitle";
import { Clear } from "@material-ui/icons";
import { AWARD_TYPES, CLOUD_FUNCTIONS } from "@sway/constants";
import React, { useState } from "react";
import { sway } from "sway";
import { functions } from "../../firebase";
import { useUserSettings } from "../../hooks";
import { useCongratulations } from "../../hooks/awards";
import { handleError, notify } from "../../utils";
import EmailLegislatorForm from "../forms/EmailLegislatorForm";
import CenteredDivCol from "../shared/CenteredDivCol";
import Award from "../user/awards/Award";
import CenteredLoading from "./CenteredLoading";

interface IProps {
    user: sway.IUser;
    locale: sway.IUserLocale | sway.ILocale;
    userVote: sway.IUserVote;
    legislators: sway.ILegislator[];
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
}

const EmailLegislatorDialog: React.FC<IProps> = ({
    user,
    locale,
    userVote,
    legislators,
    open,
    handleClose,
}) => {
    const settings = useUserSettings();
    const [isCongratulations, setIsCongratulations] = useCongratulations();
    const [isSendingEmail, setIsSendingEmail] = useState<boolean>(false);

    const [
        selectedLegislator,
        setSelectedLegislator,
    ] = useState<sway.ILegislator>(legislators[0]);

    const handleChange = (event: React.ChangeEvent<{ value: unknown }>) => {
        if (legislators) {
            const id = event.target.value as string;
            setSelectedLegislator(
                legislators.find(
                    (l) => l.externalId === id,
                ) as sway.ILegislator,
            );
        }
    };

    const handleSendEmail = ({ message }: { message: string }) => {
        console.log({ user, locale, message });
        const setter = functions.httpsCallable(
            CLOUD_FUNCTIONS.sendLegislatorEmail,
        );

        setIsSendingEmail(true);
        return setter({
            message,
            legislatorEmail: selectedLegislator.email,
            billFirestoreId: userVote.billFirestoreId,
            sender: user,
            locale,
        })
            .then((res: firebase.default.functions.HttpsCallableResult) => {
                setIsSendingEmail(false);
                if (res.data) {
                    notify({
                        level: "error",
                        title: "Failed to send email.",
                        message: res.data,
                        duration: 3000,
                    });
                } else {
                    notify({
                        level: "success",
                        title: "Email sent!",
                        message: "",
                        duration: 3000,
                    });
                    setIsCongratulations(
                        settings?.congratulations
                            ?.isCongratulateOnSocialShare === undefined
                            ? true
                            : settings?.congratulations
                                  ?.isCongratulateOnSocialShare,
                    );
                }
            })
            .catch((error) => {
                notify({
                    level: "error",
                    title: "Failed to send invites.",
                    message: "",
                    duration: 3000,
                });
                handleError(error);
                setIsSendingEmail(false);
            });
    };

    return (
        <Dialog
            open={open}
            onClose={() => handleClose(false)}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <DialogTitle id="alert-dialog-title">
                {"Increase your sway by emailing your representatives."}
                <Button
                    onClick={handleClose}
                    color="primary"
                    style={{ textAlign: "right", float: "right" }}
                >
                    <Clear />
                </Button>
            </DialogTitle>
            <DialogContent>
                {isSendingEmail && (
                    <CenteredLoading style={{ margin: "5px auto" }} />
                )}

                <CenteredDivCol style={{ width: "100%" }}>
                    <TextField
                        select
                        fullWidth
                        margin={"normal"}
                        variant="standard"
                        label="Emailing:"
                        id="legislator-selector"
                        value={selectedLegislator?.externalId}
                        onChange={handleChange}
                        style={{ paddingTop: 5, paddingBottom: 5 }}
                    >
                        {legislators?.map((l) => {
                            return (
                                <MenuItem
                                    key={l.externalId}
                                    value={l.externalId}
                                >
                                    {l.full_name}
                                </MenuItem>
                            );
                        })}
                    </TextField>
                    <EmailLegislatorForm
                        user={user}
                        legislator={selectedLegislator}
                        userVote={userVote}
                        handleSubmit={handleSendEmail}
                        handleClose={handleClose}
                    />
                </CenteredDivCol>
            </DialogContent>
            {isCongratulations && (
                <Award
                    user={user}
                    locale={locale}
                    type={AWARD_TYPES.Invite}
                    setIsCongratulations={setIsCongratulations}
                />
            )}
        </Dialog>
    );
};

export default EmailLegislatorDialog;
