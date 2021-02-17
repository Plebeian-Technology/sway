/** @format */
import { functions } from "../../firebase";
import {
    createStyles,
    Divider,
    makeStyles,
    MenuItem,
    TextField,
    useTheme,
} from "@material-ui/core";
import Button from "@material-ui/core/Button";
import Dialog from "@material-ui/core/Dialog";
import DialogContent from "@material-ui/core/DialogContent";
import DialogTitle from "@material-ui/core/DialogTitle";
import { Clear } from "@material-ui/icons";
import { AWARD_TYPES, CLOUD_FUNCTIONS } from "@sway/constants";
import { findNotCongressLocale } from "@sway/utils";
import copy from "copy-to-clipboard";
import React, { useState } from "react";
import { sway } from "sway";
import { useUserSettings } from "../../hooks";
import { useCongratulations } from "../../hooks/awards";
import { handleError, notify, swayFireClient } from "../../utils";
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

const useStyles = makeStyles(() =>
    createStyles({
        copyGroup: {
            cursor: "pointer",
        },
        copyIconContainer: {
            cursor: "pointer",
            textAlign: "center",
            fontSize: "1.5em",
        },
        copyIcon: {
            maxHeight: "1.5em",
        },
    }),
);

const EmailLegislatorDialog: React.FC<IProps> = ({
    user,
    locale,
    userVote,
    legislators,
    open,
    handleClose,
}) => {
    const classes = useStyles();
    const theme = useTheme();
    const settings = useUserSettings();
    const [isCongratulations, setIsCongratulations] = useCongratulations();
    const [isSendingEmail, setIsSendingEmail] = useState<boolean>(false);

    const [
        selectedLegislator,
        setSelectedLegislator,
    ] = useState<sway.ILegislator>(legislators[0]);

    const link = `https://${process.env.REACT_APP_ORIGIN}/invite/${user.uid}`;
    const handleCopy = (value: string) => {
        copy(value, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied!",
                    message: `Copied link to clipboard`,
                    duration: 3000,
                }),
        });
    };

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
        const setter = functions.httpsCallable(CLOUD_FUNCTIONS.sendLegislatorEmail);

        setIsSendingEmail(true);
        return setter({
            message,
            legislatorEmail: selectedLegislator.email,
            billFirestoreId: userVote.billFirestoreId,
            sender: user,
            locale,
        })
            .then((res: firebase.default.functions.HttpsCallableResult) => {
                setIsSendingEmail(false)
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
                    setIsCongratulations(true);
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
            <DialogContent style={{ cursor: "pointer" }}>
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
                    <Divider />

                    <EmailLegislatorForm
                        user={user}
                        legislator={selectedLegislator}
                        userVote={userVote}
                        setIsCongratulations={setIsCongratulations}
                        setIsSendingEmail={setIsSendingEmail}
                        handleSubmit={handleSendEmail}
                        handleClose={handleClose}
                    />
                </CenteredDivCol>
            </DialogContent>
            {isCongratulations && (
                <Award
                    user={user}
                    locale={findNotCongressLocale(user.locales)}
                    type={AWARD_TYPES.Invite}
                    setIsCongratulations={setIsCongratulations}
                />
            )}
        </Dialog>
    );
};

export default EmailLegislatorDialog;
