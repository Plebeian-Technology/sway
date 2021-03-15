/** @format */
import {
    createStyles,
    Link,
    makeStyles,
    MenuItem,
    TextField,
    Typography,
} from "@material-ui/core";
import Button from "@material-ui/core/Button";
import Dialog from "@material-ui/core/Dialog";
import DialogContent from "@material-ui/core/DialogContent";
import DialogTitle from "@material-ui/core/DialogTitle";
import { Clear } from "@material-ui/icons";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { IS_DEVELOPMENT } from "@sway/utils";
import React, { useState } from "react";
import { sway } from "sway";
import { functions } from "../../firebase";
import { useUserSettings } from "../../hooks";
import { useCongratulations } from "../../hooks/awards";
import { AWARD_TYPES, handleError, notify } from "../../utils";
import EmailLegislatorForm from "../forms/EmailLegislatorForm";
import EmailLegislatorVoteForm from "../forms/EmailLegislatorVoteForm";
import CenteredDivCol from "../shared/CenteredDivCol";
import Award from "../user/awards/Award";
import CenteredLoading from "./CenteredLoading";

interface IProps {
    user: sway.IUser;
    locale: sway.IUserLocale | sway.ILocale;
    userVote?: sway.IUserVote;
    legislators: sway.ILegislator[];
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
}

const useStyles = makeStyles(() =>
    createStyles({
        noEmailContent: {
            textAlign: "left",
            alignSelf: "flex-start",
            marginBottom: 20,
        },
        noEmailContentText: {
            marginTop: 10,
            marginBottom: 10,
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
    const settings = useUserSettings();
    const [isCongratulations, setIsCongratulations] = useCongratulations();
    const [isSendingEmail, setIsSendingEmail] = useState<boolean>(false);

    const [
        selectedLegislator,
        setSelectedLegislator,
    ] = useState<sway.ILegislator>(legislators[0]);

    const setClosed = () => {
        setIsCongratulations(false);
        handleClose(false);
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

    const legislatorEmail = () => {
        if (IS_DEVELOPMENT) {
            return "legis@sway.vote";
        }
        return selectedLegislator.email;
    };

    const handleSendEmail = ({ message }: { message: string }) => {
        if (!userVote) return;

        const setter = functions.httpsCallable(
            CLOUD_FUNCTIONS.sendLegislatorEmail,
        );

        setIsSendingEmail(true);
        return setter({
            message,
            legislatorEmail: legislatorEmail(),
            billFirestoreId: userVote.billFirestoreId,
            support: userVote.support,
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
                    title: "Failed to send legislator email.",
                    message: "",
                    duration: 3000,
                });
                handleError(error);
                setIsSendingEmail(false);
            });
    };

    const content = () => {
        if (!selectedLegislator.email) {
            IS_DEVELOPMENT &&
                console.log(
                    `(dev) missing email for ${selectedLegislator.full_name} - ${selectedLegislator.externalId}`,
                );
            return (
                <div className={classes.noEmailContent}>
                    <Typography className={classes.noEmailContentText}>
                        Unfortunately, it looks like we don't have an email
                        address for {selectedLegislator.title}{" "}
                        {selectedLegislator.full_name} in our database.
                    </Typography>
                </div>
            );
        }
        if (selectedLegislator.email?.startsWith("http")) {
            return (
                <div className={classes.noEmailContent}>
                    <Typography className={classes.noEmailContentText}>
                        Unfortunately, it's not possible to email{" "}
                        {selectedLegislator.title}{" "}
                        {selectedLegislator.full_name} directly.
                    </Typography>
                    <Typography className={classes.noEmailContentText}>
                        You can, however, email them through their website at:
                    </Typography>
                    <Link
                        className={classes.noEmailContentText}
                        target="_blank"
                        href={selectedLegislator.email}
                    >
                        {selectedLegislator.email}
                    </Link>
                    <Typography className={classes.noEmailContentText}>
                        We know this isn't a great solution, connecting with
                        your *representatives* shouldn't be so difficult but
                        that's one reason we built Sway, to make it easier for
                        you to take action.
                    </Typography>
                </div>
            );
        }
        if (userVote) {
            return (
                <EmailLegislatorVoteForm
                    user={user}
                    legislator={selectedLegislator}
                    userVote={userVote}
                    handleSubmit={handleSendEmail}
                    handleClose={setClosed}
                />
            );
        }

        return (
            <EmailLegislatorForm
                user={user}
                legislator={selectedLegislator}
                handleSubmit={handleSendEmail}
                handleClose={setClosed}
            />
        );
    };

    return (
        <Dialog
            open={open}
            onClose={setClosed}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <DialogTitle id="alert-dialog-title" style={{ paddingBottom: 0 }}>
                {"Increase your sway by emailing your representatives."}
                <Button
                    onClick={handleClose}
                    color="primary"
                    style={{ textAlign: "right", float: "right" }}
                >
                    <Clear />
                </Button>
            </DialogTitle>
            <DialogContent style={{ paddingTop: 0 }}>
                {isSendingEmail && (
                    <CenteredLoading style={{ margin: "5px auto" }} />
                )}

                {selectedLegislator.email &&
                    !selectedLegislator.email.startsWith("http") && (
                        <Typography>
                            Don't know what to say? Here's an editable prompt
                            for you.
                        </Typography>
                    )}

                {legislators.length > 0 && (
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
                        {content()}
                    </CenteredDivCol>
                )}
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
