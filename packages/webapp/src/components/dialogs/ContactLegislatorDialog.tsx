/** @format */
import { Link, MenuItem, TextField } from "@mui/material";
import Dialog from "@mui/material/Dialog";
import DialogContent from "@mui/material/DialogContent";
import DialogTitle from "@mui/material/DialogTitle";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { formatPhone, IS_DEVELOPMENT, logDev, titleize } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import React, { useState } from "react";
import { sway } from "sway";
import { functions } from "../../firebase";
import { GAINED_SWAY_MESSAGE, handleError, notify, withTadas } from "../../utils";
import ContactLegislatorForm from "../forms/ContactLegislatorForm";
import CenteredLoading from "./CenteredLoading";

interface IProps {
    user: sway.IUser;
    locale: sway.IUserLocale | sway.ILocale;
    userVote?: sway.IUserVote;
    legislators: sway.ILegislator[];
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
    type: "email" | "phone";
}

const ContactLegislatorDialog: React.FC<IProps> = ({
    user,
    locale,
    userVote,
    legislators,
    open,
    handleClose,
    type,
}) => {
    const [isSending, setSending] = useState<boolean>(false);

    const [selectedLegislator, setSelectedLegislator] = useState<sway.ILegislator>(legislators[0]);

    const setClosed = () => {
        handleClose(false);
    };

    const handleChange = (event: React.ChangeEvent<{ value: unknown }>) => {
        if (legislators) {
            const id = event.target.value as string;
            setSelectedLegislator(legislators.find((l) => l.externalId === id) as sway.ILegislator);
        }
    };

    const getLegislatorEmail = () => {
        if (IS_DEVELOPMENT) {
            return "legis@sway.vote";
        }
        return selectedLegislator.email;
    };
    const getLegislatorPhone = (): string => {
        if (IS_DEVELOPMENT) {
            return formatPhone("1234567890");
        }
        return formatPhone(selectedLegislator.phone);
    };

    const handleSend = ({ message }: { message: string }) => {
        if (!userVote) return;
        const action = type === "phone" ? "Phone call" : "Email";
        const func =
            type === "phone"
                ? CLOUD_FUNCTIONS.sendLegislatorPhoneCall
                : CLOUD_FUNCTIONS.sendLegislatorEmail;

        const setter = httpsCallable(functions, func);

        setSending(true);
        return setter({
            message,
            legislatorPhone: getLegislatorPhone(),
            legislatorEmail: getLegislatorEmail(),
            billFirestoreId: userVote.billFirestoreId,
            support: userVote.support,
            sender: user,
            locale,
        })
            .then((res: firebase.default.functions.HttpsCallableResult) => {
                setSending(false);
                if (res.data) {
                    notify({
                        level: "error",
                        title: `Failed to send ${action.toLowerCase()}.`,
                        message: res.data,
                    });
                } else {
                    notify({
                        level: "success",
                        title: `${action} sent!`,
                        message: withTadas(GAINED_SWAY_MESSAGE),
                        tada: true,
                    });
                }
            })
            .catch((error) => {
                notify({
                    level: "error",
                    title: `Failed to send ${action.toLowerCase()} to legislator.`,
                });
                handleError(error);
                setSending(false);
            });
    };

    const content = () => {
        if (type === "email" && !selectedLegislator.email) {
            logDev(
                `missing EMAIL for ${selectedLegislator.full_name} - ${selectedLegislator.externalId}`,
            );
            return (
                <span>
                    Unfortunately, it looks like we don't have an email address for{" "}
                    {selectedLegislator.title} {selectedLegislator.full_name} in our database.
                </span>
            );
        }
        if (type === "phone" && !selectedLegislator.phone) {
            logDev(
                `missing PHONE for ${selectedLegislator.full_name} - ${selectedLegislator.externalId}`,
            );
            return (
                <span>
                    Unfortunately, it looks like we don't have a phone number for{" "}
                    {selectedLegislator.title} {selectedLegislator.full_name} in our database.
                </span>
            );
        }
        if (type === "email" && selectedLegislator.email?.startsWith("http")) {
            return (
                <div>
                    <span>
                        Unfortunately, it's not possible to email {selectedLegislator.title}{" "}
                        {selectedLegislator.full_name} directly.
                    </span>
                    <span>You can, however, email them through their website at:</span>
                    <Link target="_blank" href={selectedLegislator.email}>
                        {selectedLegislator.email}
                    </Link>
                    <span>
                        We know this isn't a great solution, connecting with your *representatives*
                        shouldn't be so difficult but that's one reason we built Sway, to make it
                        easier for you to take action.
                    </span>
                </div>
            );
        }
        return (
            <ContactLegislatorForm
                type={type}
                user={user}
                legislator={selectedLegislator}
                userVote={userVote}
                handleSubmit={handleSend}
                handleClose={handleClose}
            />
        );
    };

    const verbing = type === "phone" ? "calling" : "emailing";

    return (
        <Dialog
            open={open}
            onClose={setClosed}
            aria-labelledby="contact-legislator-dialog"
            aria-describedby="contact-legislator-dialog"
        >
            <DialogTitle id="contact-legislator-dialog">
                {`Increase your sway by ${verbing} your representatives.`}
            </DialogTitle>
            <DialogContent>
                {isSending && <CenteredLoading />}
                <div className="col">
                    <div className="row">
                        <span>Don't know what to say? Here's an editable prompt for you.</span>
                    </div>
                    {legislators.length > 0 && (
                        <div className="row w-100">
                            <div className="col">
                                <TextField
                                    select
                                    fullWidth
                                    margin={"normal"}
                                    variant="standard"
                                    label={titleize(verbing)}
                                    id="legislator-selector"
                                    value={selectedLegislator?.externalId}
                                    onChange={handleChange}
                                >
                                    {legislators?.map((l) => {
                                        return (
                                            <MenuItem key={l.externalId} value={l.externalId}>
                                                {l.full_name}
                                            </MenuItem>
                                        );
                                    })}
                                </TextField>
                                {content()}
                            </div>
                        </div>
                    )}
                </div>
            </DialogContent>
        </Dialog>
    );
};

export default ContactLegislatorDialog;
