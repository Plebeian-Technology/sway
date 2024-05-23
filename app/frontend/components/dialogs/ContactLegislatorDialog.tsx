/** @format */

import { CLOUD_FUNCTIONS, EXECUTIVE_BRANCH_TITLES, IS_DEVELOPMENT, Support } from "app/frontend/sway_constants";
import {
    getFullUserAddress,
    isAtLargeLegislator,
    logDev,
    notify,
    titleize,
} from "app/frontend/sway_utils";
import copy from "copy-to-clipboard";
import { Form, Formik } from "formik";
import { useState } from "react";
import { Button, Modal } from "react-bootstrap";
import { FiMail, FiX } from "react-icons/fi";
import { sway } from "sway";
import { useLocale } from "../../hooks/useLocales";
import { useUser } from "../../hooks/users/useUser";

import ContactLegislatorForm from "../forms/ContactLegislatorForm";
import SwaySpinner from "../SwaySpinner";
import { formatPhone } from "app/frontend/sway_utils/phone";

interface IProps {
    userVote?: sway.IUserVote;
    legislators: sway.ILegislator[];
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
    type: "email" | "phone";
}

const ContactLegislatorDialog: React.FC<IProps> = ({
    userVote,
    legislators,
    open,
    handleClose,
    type,
}) => {
    const user = useUser();
    const [locale] = useLocale();

    const [isSending, setSending] = useState<boolean>(false);

    const [selectedLegislator, setSelectedLegislator] = useState<sway.ILegislator>(legislators[0]);

    const setClosed = () => {
        handleClose(false);
    };

    const handleChangeLegislator = (event: React.ChangeEvent<{ value: unknown }>) => {
        if (legislators) {
            const id = event.target.value as string;
            setSelectedLegislator(legislators.find((l) => l.externalId === id) as sway.ILegislator);
        }
    };

    // const getLegislatorEmail = () => {
    //     if (IS_DEVELOPMENT) {
    //         return "legis@sway.vote";
    //     }
    //     return selectedLegislator.email;
    // };
    // const getLegislatorPhone = (): string => {
    //     if (IS_DEVELOPMENT) {
    //         return formatPhone("1234567890");
    //     }
    //     return formatPhone(selectedLegislator.phone);
    // };

    const handleSubmit = (values: { message: string }) => {
        logDev("ContactLegislatorDialog.handleSubmit.values -", values);
        if (!userVote || !values.message) return;

        const action = type === "phone" ? "Phone call" : "Email";
        const func =
            type === "phone"
                ? CLOUD_FUNCTIONS.sendLegislatorPhoneCall
                : CLOUD_FUNCTIONS.sendLegislatorEmail;


        setSending(true);
        // return () => ({
        //     message: values.message,
        //     legislatorPhone: getLegislatorPhone(),
        //     legislatorEmail: getLegislatorEmail(),
        //     billExternalId: userVote.billExternalId,
        //     support: userVote.support,
        //     sender: user,
        //     locale,
        // })
        //     .then((res: firebase.default.functions.HttpsCallableResult) => {
        //         setSending(false);
        //         if (res.data) {
        //             notify({
        //                 level: "error",
        //                 title: `Failed to send ${action.toLowerCase()}.`,
        //                 message: res.data,
        //             });
        //         } else {
        //             notify({
        //                 level: "success",
        //                 title: `${action} sent!`,
        //                 message: withTadas(GAINED_SWAY_MESSAGE),
        //                 tada: true,
        //             });
        //         }
        //     })
        //     .catch((error) => {
        //         notify({
        //             level: "error",
        //             title: `Failed to send ${action.toLowerCase()} to legislator.`,
        //         });
        //         handleError(error);
        //         setSending(false);
        //     });
    };

    const address = (): string => {
        return getFullUserAddress(user);
    };

    const registeredVoter = (): string => {
        if (!user.isRegisteredToVote) {
            return "I";
        }
        return "I am registered to vote and";
    };

    const shortSupport = (): string => {
        if (!userVote) return "";

        if (userVote.support === Support.For) {
            return "support";
        }
        return "oppose";
    };

    const longSupport = (): string => {
        if (!userVote) return "";

        if (EXECUTIVE_BRANCH_TITLES.includes(selectedLegislator.title.toLowerCase())) {
            return shortSupport();
        }
        if (userVote.support === Support.For) {
            return "vote in support of";
        }
        return `vote ${Support.Against}`;
    };

    const residence = (): string => {
        if (
            isAtLargeLegislator({
                district: selectedLegislator.district.number,
                regionCode: selectedLegislator.district.regionCode,
            })
        ) {
            return `in ${titleize(user.city)}`;
        }
        return `in your district`;
    };

    const getLegislatorTitle = (): string => {
        if (selectedLegislator.title?.toLowerCase() === "councilmember") {
            return "Council Member";
        }
        return selectedLegislator.title;
    };

    const defaultMessage = (): string => {
        const userVoteText = userVote
            ? `Please ${longSupport()} bill ${userVote.billExternalId}.\n\r`
            : `I am ${
                  type === "phone" ? "calling" : "writing"
              } to you today because I would like you to support...\n\r`;
        return `Hello ${getLegislatorTitle()} ${selectedLegislator.last_name}, my name is ${
            user.name
        } and ${registeredVoter()} reside ${residence()} at ${titleize(
            address(),
        )}.\n\r${userVoteText}Thank you, ${user.name}`;
    };

    const getLegislatorEmail = (): string => {
        if (IS_DEVELOPMENT) {
            return "legis@sway.vote";
        }
        return selectedLegislator.email;
    };

    const getLegislatorEmailPreview = (): string => {
        if (IS_DEVELOPMENT) {
            return `(dev) legis@sway.vote - (prod) ${selectedLegislator.email}`;
        }
        return selectedLegislator.email;
    };

    const getLegislatorPhone = (): string => {
        if (IS_DEVELOPMENT) {
            return formatPhone("1234567890");
        }
        return formatPhone(selectedLegislator.phone);
    };

    const getLegislatorPhonePreview = (): string => {
        if (IS_DEVELOPMENT) {
            return `(dev) ${formatPhone("1234567890")} - (prod) ${formatPhone(
                selectedLegislator.phone,
            )}`;
        }
        return formatPhone(selectedLegislator.phone);
    };

    const handleCopy = (): string => {
        const toCopy = type === "phone" ? getLegislatorPhone() : getLegislatorEmail();
        copy(toCopy, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: `Copied ${type} to clipboard.`,
                }),
        });
        return "";
    };

    const render = () => {
        if (type === "email" && !selectedLegislator.email) {
            logDev(
                `missing EMAIL for ${selectedLegislator.fullName} - ${selectedLegislator.externalId}`,
            );
            return (
                <span>
                    Unfortunately, it looks like we don't have an email address for{" "}
                    {selectedLegislator.title} {selectedLegislator.fullName} in our database.
                </span>
            );
        }
        if (type === "phone" && !selectedLegislator.phone) {
            logDev(
                `missing PHONE for ${selectedLegislator.fullName} - ${selectedLegislator.externalId}`,
            );
            return (
                <span>
                    Unfortunately, it looks like we don't have a phone number for{" "}
                    {selectedLegislator.title} {selectedLegislator.fullName} in our database.
                </span>
            );
        }
        if (type === "email" && selectedLegislator.email?.startsWith("http")) {
            return (
                <div>
                    <span>
                        Unfortunately, it's not possible to email {selectedLegislator.title}{" "}
                        {selectedLegislator.fullName} directly.
                    </span>
                    <span>You can, however, email them through their website at:</span>
                    <a target="_blank" href={selectedLegislator.email}>
                        {selectedLegislator.email}
                    </a>
                    <span>
                        We know this isn't a great solution, connecting with your *representatives*
                        shouldn't be so difficult but that's one reason we built Sway, to make it
                        easier for you to take action.
                    </span>
                </div>
            );
        }

        const methods = {
            address,
            registeredVoter,
            shortSupport,
            longSupport,
            residence,
            defaultMessage,
            getLegislatorTitle,
            getLegislatorEmail,
            getLegislatorEmailPreview,
            getLegislatorPhone,
            getLegislatorPhonePreview,
            handleCopy,
        };

        return (
            <ContactLegislatorForm
                type={type}
                user={user}
                legislator={selectedLegislator}
                userVote={userVote}
                methods={methods}
                legislators={legislators}
                selectedLegislator={selectedLegislator}
                handleChangeLegislator={handleChangeLegislator}
            />
        );
    };

    // logDev("ContactLegislatorDialog.user -", user);
    const verbing = type === "phone" ? "calling" : "emailing";

    return (
        <Modal
            centered
            show={open}
            onHide={setClosed}
            aria-labelledby="contact-legislator-dialog"
            aria-describedby="contact-legislator-dialog"
        >
            <Formik
                initialValues={{ message: defaultMessage() }}
                onSubmit={handleSubmit}
                enableReinitialize={true}
            >
                <Form>
                    <Modal.Header id="contact-legislator-dialog">
                        <Modal.Title>{`Increase your sway by ${verbing} your representatives.`}</Modal.Title>
                    </Modal.Header>
                    <Modal.Body>{render()}</Modal.Body>
                    <Modal.Footer>
                        <SwaySpinner isHidden={!isSending} />
                        <Button onClick={handleClose} variant="secondary">
                            <FiX />
                            &nbsp;<span className="align-text-top">Cancel</span>
                        </Button>
                        <Button type="submit" variant="primary">
                            <FiMail />
                            &nbsp;
                            <span className="align-text-top">Send</span>
                        </Button>
                    </Modal.Footer>
                </Form>
            </Formik>
        </Modal>
    );
};

export default ContactLegislatorDialog;
