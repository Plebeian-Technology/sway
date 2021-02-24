/** @format */
import {
    createStyles,
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
import PhoneLegislatorForm from "../forms/PhoneLegislatorForm";
import PhoneLegislatorVoteForm from "../forms/PhoneLegislatorVoteForm";
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
        noPhoneCallContent: {
            textAlign: "left",
            alignSelf: "flex-start",
            marginBottom: 20,
        },
        noPhoneCallContentText: {
            marginTop: 10,
            marginBottom: 10,
        },
    }),
);

const PhoneLegislatorDialog: React.FC<IProps> = ({
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
    const [isSendingPhoneCall, setIsSendingPhoneCall] = useState<boolean>(
        false,
    );

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

    const legislatorPhone = () => {
        if (IS_DEVELOPMENT) {
            return "legis@sway.vote";
        }
        return selectedLegislator.phone;
    };

    const handleSendPhoneCall = ({ message }: { message: string }) => {
        console.log({ user, locale, message });
        const setter = functions.httpsCallable(
            CLOUD_FUNCTIONS.sendLegislatorPhoneCall,
        );

        setIsSendingPhoneCall(true);
        return setter({
            message,
            legislatorPhone: legislatorPhone(),
            billFirestoreId: userVote?.billFirestoreId,
            sender: user,
            locale,
        })
            .then((res: firebase.default.functions.HttpsCallableResult) => {
                setIsSendingPhoneCall(false);
                if (res.data) {
                    notify({
                        level: "error",
                        title: "Failed to send phone.",
                        message: res.data,
                        duration: 3000,
                    });
                } else {
                    notify({
                        level: "success",
                        title: "Phone call sent!",
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
                setIsSendingPhoneCall(false);
            });
    };

    const content = () => {
        if (!selectedLegislator.phone) {
            console.error(
                `missing phone for ${selectedLegislator.full_name} - ${selectedLegislator.externalId}`,
            );
            return (
                <div className={classes.noPhoneCallContent}>
                    <Typography className={classes.noPhoneCallContentText}>
                        Unfortunately, it looks like we don't have a phone
                        number for {selectedLegislator.title}{" "}
                        {selectedLegislator.full_name} in our database.
                    </Typography>
                    <Typography className={classes.noPhoneCallContentText}>
                        Sorry about that, you don't need to do anything else -
                        we've sent a notification to the people who need to
                        know.
                    </Typography>
                </div>
            );
        }
        if (userVote) {
            return (
                <PhoneLegislatorVoteForm
                    user={user}
                    legislator={selectedLegislator}
                    userVote={userVote}
                    handleSubmit={handleSendPhoneCall}
                    handleClose={handleClose}
                />
            );
        }

        return (
            <PhoneLegislatorForm
                user={user}
                legislator={selectedLegislator}
                handleSubmit={handleSendPhoneCall}
                handleClose={handleClose}
            />
        );
    };

    return (
        <Dialog
            open={open}
            onClose={() => handleClose(false)}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <DialogTitle id="alert-dialog-title" style={{ paddingBottom: 0 }}>
                {"Increase your sway by calling your representatives."}
                <Button
                    onClick={handleClose}
                    color="primary"
                    style={{ textAlign: "right", float: "right" }}
                >
                    <Clear />
                </Button>
            </DialogTitle>
            <DialogContent style={{ paddingTop: 0 }}>
                {isSendingPhoneCall && (
                    <CenteredLoading style={{ margin: "5px auto" }} />
                )}

                <Typography>
                    Don't know what to say? Here's an editable prompt for you.
                </Typography>

                {legislators.length > 0 && (
                    <CenteredDivCol style={{ width: "100%" }}>
                        <TextField
                            select
                            fullWidth
                            margin={"normal"}
                            variant="standard"
                            label="Calling:"
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

export default PhoneLegislatorDialog;
