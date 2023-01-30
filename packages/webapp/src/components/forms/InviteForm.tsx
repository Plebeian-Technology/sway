/** @format */

import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isCongressLocale, isEmptyObject, logDev } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import React, { useState } from "react";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { FiMinus, FiPlus, FiSend } from "react-icons/fi";
import { sway } from "sway";
import * as yup from "yup";
import { functions } from "../../firebase";
import { GAINED_SWAY_MESSAGE, handleError, notify, withTadas } from "../../utils";
import SwaySpinner from "../SwaySpinner";

const VALIDATION_SCHEMA = yup.array(yup.string().email());

interface IProps {
    user: sway.IUser;
    isSendingInvites: boolean;
    setIsSendingInvites: React.Dispatch<React.SetStateAction<boolean>>;
}

interface ISentInvitesResponseData {
    sent: string[];
    rejected: string[];
}

const InviteForm: React.FC<IProps> = ({ user, isSendingInvites, setIsSendingInvites }) => {
    const [emails, setEmails] = useState<string[]>([""]);

    const handleSubmit = (e: React.MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        e.stopPropagation();

        if (!VALIDATION_SCHEMA.isValidSync(emails)) {
            return;
        }

        setIsSendingInvites(true);

        logDev("InviteForm.handleSubmit.emails", { emails: emails.filter(Boolean) });
        const setter = httpsCallable(functions, CLOUD_FUNCTIONS.sendUserInvites);

        return setter({
            emails: emails.filter(Boolean),
            sender: user,
            locale:
                user.locales.filter((l) => !isCongressLocale(l)).first() || user.locales.first(),
        })
            .then((res: firebase.default.functions.HttpsCallableResult) => {
                setIsSendingInvites(false);
                const data = res.data as string | ISentInvitesResponseData;
                if (!data) {
                    logDev("Unexpected no data in response from sendUserInvite. Response - ", res);
                    notify({
                        level: "error",
                        title: "Failed to send invites.",
                    });
                    return;
                }
                logDev("Data from send invites response", data);
                if (typeof data === "string") {
                    notify({
                        level: "error",
                        title: "Failed to send invites.",
                        message: data,
                    });
                } else {
                    const rejected = !isEmptyObject(data.rejected)
                        ? ` but rejected for ${data.rejected.join(", ")}`
                        : "";
                    notify({
                        level: "success",
                        title: "Invites sent!",
                        message: withTadas(
                            `Invites sent to ${data.sent.join(
                                ", ",
                            )}${rejected}. ${GAINED_SWAY_MESSAGE}`,
                        ),
                        tada: true,
                    });
                }
            })
            .catch((error) => {
                setIsSendingInvites(false);
                notify({
                    level: "error",
                    title: "Failed to send invites.",
                });
                handleError(error);
            });
    };

    return (
        <div className="col">
            {emails.map((email, index) => {
                return (
                    <BootstrapForm.Group
                        key={`emails.${index}`}
                        controlId={`emails.${index}`}
                        className="my-3"
                    >
                        <BootstrapForm.Control
                            type="email"
                            className="form-control invite-email"
                            placeholder="Enter email..."
                            name={`emails.${index}`}
                            isInvalid={!VALIDATION_SCHEMA.isValid(email)}
                            onChange={(event) => {
                                event.preventDefault();
                                event.stopPropagation();
                                setEmails((current) => {
                                    return current.map((e, i) => {
                                        if (i === index) {
                                            return event.target.value;
                                        } else {
                                            return e;
                                        }
                                    });
                                });
                            }}
                        />
                    </BootstrapForm.Group>
                );
            })}
            <div className="row">
                <div className="col-1">
                    <Button
                        variant="outline-primary"
                        onClick={() => setEmails((current) => current.concat(""))}
                    >
                        <FiPlus />
                    </Button>
                </div>
                <div className="col-1">
                    <Button
                        variant="outline-primary"
                        onClick={() => setEmails((current) => current.slice(0, current.length - 1))}
                    >
                        <FiMinus />
                    </Button>
                </div>
                <div className="col-8">&nbsp;</div>
                <div className="col-1">
                    <SwaySpinner isHidden={!isSendingInvites} />
                </div>
                <div className="col-1">
                    <Button onClick={handleSubmit}>
                        <FiSend />
                    </Button>
                </div>
            </div>
        </div>
    );
};

export default InviteForm;
