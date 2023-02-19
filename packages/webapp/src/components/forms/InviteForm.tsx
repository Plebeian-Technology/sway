/** @format */

import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isEmptyObject, logDev } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import { useCallback, useState } from "react";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { FiMinus, FiPlus, FiSend } from "react-icons/fi";
import * as yup from "yup";
import { functions } from "../../firebase";
import { useUserLocale } from "../../hooks/locales/useUserLocale";
import { GAINED_SWAY_MESSAGE, handleError, notify, withTadas } from "../../utils";
import SwaySpinner from "../SwaySpinner";

const VALIDATION_SCHEMA = yup.array(yup.string().email());

interface IProps {
    isSendingInvites: boolean;
    setSendingInvites: React.Dispatch<React.SetStateAction<boolean>>;
}

interface ISentInvitesResponseData {
    sent: string[];
    rejected: string[];
}

const DEFAULT_EMAILS = [""];

const InviteForm: React.FC<IProps> = ({ isSendingInvites, setSendingInvites }) => {
    const userLocale = useUserLocale();
    const [emails, setEmails] = useState<string[]>(DEFAULT_EMAILS);

    const handleAddEmail = useCallback(
        () => setEmails((current) => current.concat("")),
        [setEmails],
    );
    const handleRemoveEmail = useCallback(
        () => setEmails((current) => current.slice(0, current.length - 1)),
        [setEmails],
    );

    const handleSetEmails = useCallback(
        (event: React.ChangeEvent<HTMLInputElement>) => {
            event.preventDefault();
            event.stopPropagation();

            const { id, value } = event.target;
            const index = Number(id);

            setEmails((current) => {
                return current.map((e, i) => {
                    if (i === index) {
                        return value;
                    } else {
                        return e;
                    }
                });
            });
        },
        [setEmails],
    );

    const handleSubmit = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            e.stopPropagation();

            if (!VALIDATION_SCHEMA.isValidSync(emails)) {
                return;
            }

            setSendingInvites(true);

            logDev("InviteForm.handleSubmit.emails", { emails: emails.filter(Boolean) });
            const setter = httpsCallable(functions, CLOUD_FUNCTIONS.sendUserInvites);

            return setter({
                emails: emails.filter(Boolean),
                locale: userLocale,
            })
                .then((res: firebase.default.functions.HttpsCallableResult) => {
                    setSendingInvites(false);
                    const data = res.data as string | ISentInvitesResponseData;
                    if (!data) {
                        logDev(
                            "Unexpected no data in response from sendUserInvite. Response - ",
                            res,
                        );
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
                    setSendingInvites(false);
                    handleError(error);
                });
        },
        [emails, setSendingInvites, userLocale],
    );

    return (
        <div className="col">
            {emails.map((email, index) => {
                return (
                    <BootstrapForm.Group key={`emails.${index}`} className="my-3">
                        <BootstrapForm.Control
                            id={index.toString()}
                            type="email"
                            className="form-control invite-email"
                            placeholder="Enter email..."
                            name={`emails.${index}`}
                            isInvalid={!VALIDATION_SCHEMA.isValid(email)}
                            onChange={handleSetEmails}
                            disabled={isSendingInvites}
                        />
                    </BootstrapForm.Group>
                );
            })}
            <div className="row">
                <div className="col-2 col-lg-1">
                    <Button
                        variant="outline-primary"
                        onClick={handleAddEmail}
                        disabled={isSendingInvites}
                    >
                        <FiPlus />
                    </Button>
                </div>
                <div className="col-2 col-lg-1">
                    <Button
                        variant="outline-primary"
                        onClick={handleRemoveEmail}
                        disabled={isSendingInvites}
                    >
                        <FiMinus />
                    </Button>
                </div>
                <div className="col-4 col-lg-8">&nbsp;</div>
                <div className="col-2 col-lg-1">
                    <SwaySpinner isHidden={!isSendingInvites} />
                </div>
                <div className="col-2 col-lg-1">
                    <Button onClick={handleSubmit} disabled={isSendingInvites}>
                        <FiSend />
                    </Button>
                </div>
            </div>
        </div>
    );
};

export default InviteForm;
