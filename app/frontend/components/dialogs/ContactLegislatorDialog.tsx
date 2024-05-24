/** @format */

import { EXECUTIVE_BRANCH_TITLES, IS_DEVELOPMENT, Support } from "app/frontend/sway_constants";
import { getFullUserAddress, isAtLargeLegislator, logDev, notify, titleize } from "app/frontend/sway_utils";
import copy from "copy-to-clipboard";
import { Form, Formik } from "formik";
import { useCallback, useMemo } from "react";
import { Button, Modal } from "react-bootstrap";
import { FiMail, FiPhoneCall, FiX } from "react-icons/fi";
import { sway } from "sway";
import { useLocale } from "../../hooks/useLocales";
import { useUser } from "../../hooks/users/useUser";

import { formatPhone } from "app/frontend/sway_utils/phone";
import ContactLegislatorForm from "../forms/ContactLegislatorForm";

interface IProps {
    userVote?: sway.IUserVote;
    legislator: sway.ILegislator;
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
    type: "email" | "phone";
}

const ContactLegislatorDialog: React.FC<IProps> = ({ userVote, legislator, open, handleClose, type }) => {
    const user = useUser();
    const [locale] = useLocale();

    const setClosed = useCallback(() => {
        handleClose(false);
    }, [handleClose]);

    // const getLegislatorEmail = () => {
    //     if (IS_DEVELOPMENT) {
    //         return "legis@sway.vote";
    //     }
    //     return legislator.email;
    // };
    // const getLegislatorPhone = (): string => {
    //     if (IS_DEVELOPMENT) {
    //         return formatPhone("1234567890");
    //     }
    //     return formatPhone(legislator.phone);
    // };

    const handleSubmit = useCallback(
        (values: { message: string }) => {
            logDev("ContactLegislatorDialog.handleSubmit.values -", values);

            if (type === "email") {
                window.location.href = `mailto:${legislator.email}?subject=Concern Regarding Legislation&body=${values.message}`;
            } else {
                window.location.href = `tel:${legislator.phone}`;
            }
        },
        [legislator.email, legislator.phone, type],
    );

    const address = useCallback((): string => {
        return getFullUserAddress(user);
    }, [user]);

    const registeredVoter = useCallback((): string => {
        if (!user.isRegisteredToVote) {
            return "I";
        }
        return "I am registered to vote and";
    }, [user.isRegisteredToVote]);

    const shortSupport = useCallback((): string => {
        if (!userVote) return "";

        if (userVote.support === Support.For) {
            return "support";
        }
        return "oppose";
    }, [userVote]);

    const longSupport = useCallback((): string => {
        if (!userVote) return "";

        if (EXECUTIVE_BRANCH_TITLES.includes(legislator.title.toLowerCase())) {
            return shortSupport();
        }
        if (userVote.support === Support.For) {
            return "vote in support of";
        }
        return `vote ${Support.Against}`;
    }, [legislator.title, shortSupport, userVote]);

    const residence = useCallback((): string => {
        if (isAtLargeLegislator(legislator.district)) {
            return `in ${titleize(locale.city)}`;
        }
        return `in your district`;
    }, [legislator.district, locale.city]);

    const getLegislatorTitle = useCallback((): string => {
        if (legislator.title?.toLowerCase() === "councilmember") {
            return "Council Member";
        }
        return legislator.title;
    }, [legislator.title]);

    const userVoteText = useMemo(
        () =>
            userVote
                ? `Please ${longSupport()} bill ${userVote.bill.externalId}.\n\r`
                : `I am ${
                      type === "phone" ? "calling" : "writing"
                  } to you today because I would like you to support... {NAME OF BILL}.\n\r`,
        [longSupport, type, userVote],
    );

    const defaultMessage = useCallback((): string => {
        return `Hello ${getLegislatorTitle()} ${legislator.lastName}, my name is {YOUR NAME} and ${registeredVoter()} reside ${residence()} at {YOUR ADDRESS}.\n\r${userVoteText} Thank you, {YOUR NAME}`;
    }, [getLegislatorTitle, legislator.lastName, registeredVoter, residence, userVoteText]);

    const getLegislatorEmail = useCallback((): string => {
        if (IS_DEVELOPMENT) {
            return "legis@sway.vote";
        }
        return legislator.email;
    }, [legislator.email]);

    const getLegislatorEmailPreview = useCallback((): string => {
        if (IS_DEVELOPMENT) {
            return `(dev) legis@sway.vote - (prod) ${legislator.email}`;
        }
        return legislator.email;
    }, [legislator.email]);

    const getLegislatorPhone = useCallback((): string => {
        if (IS_DEVELOPMENT) {
            return formatPhone("1234567890");
        }
        return formatPhone(legislator.phone);
    }, [legislator.phone]);

    const getLegislatorPhonePreview = useCallback((): string => {
        if (IS_DEVELOPMENT) {
            return `(dev) ${formatPhone("1234567890")} - (prod) ${formatPhone(legislator.phone)}`;
        }
        return formatPhone(legislator.phone);
    }, [legislator.phone]);

    const handleCopy = useCallback((): string => {
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
    }, [getLegislatorEmail, getLegislatorPhone, type]);

    const render = useMemo(() => {
        if (type === "email" && !legislator.email) {
            logDev(`missing EMAIL for ${legislator.fullName} - ${legislator.externalId}`);
            return (
                <span>
                    Unfortunately, it looks like we don't have an email address for {legislator.title}{" "}
                    {legislator.fullName} in our database.
                </span>
            );
        }
        if (type === "phone" && !legislator.phone) {
            logDev(`missing PHONE for ${legislator.fullName} - ${legislator.externalId}`);
            return (
                <span>
                    Unfortunately, it looks like we don't have a phone number for {legislator.title}{" "}
                    {legislator.fullName} in our database.
                </span>
            );
        }
        if (type === "email" && legislator.email?.startsWith("http")) {
            return (
                <div>
                    <span>
                        Unfortunately, it's not possible to email {legislator.title} {legislator.fullName} directly.
                    </span>
                    <span>You can, however, email them through their website at:</span>
                    <a target="_blank" href={legislator.email}>
                        {legislator.email}
                    </a>
                    <span>
                        We know this isn't a great solution, connecting with your *representatives* shouldn't be so
                        difficult but that's one reason we built Sway, to make it easier for you to take action.
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
                legislator={legislator}
                userVote={userVote}
                methods={methods}
            />
        );
    }, [
        address,
        defaultMessage,
        getLegislatorEmail,
        getLegislatorEmailPreview,
        getLegislatorPhone,
        getLegislatorPhonePreview,
        getLegislatorTitle,
        handleCopy,
        legislator,
        longSupport,
        registeredVoter,
        residence,
        shortSupport,
        type,
        user,
        userVote,
    ]);

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
            <Formik initialValues={{ message: defaultMessage() }} onSubmit={handleSubmit} enableReinitialize={true}>
                <Form>
                    <Modal.Header id="contact-legislator-dialog">
                        <Modal.Title>{`Increase your sway by ${verbing} your representatives.`}</Modal.Title>
                    </Modal.Header>
                    <Modal.Body>
                        {/* {legislator && (
                <Form.Group controlId="legislator" className="my-2">
                    <Form.Label>{titleize(verbing)}:</Form.Label>
                    <Form.Control
                        as="select"
                        name="legislator"
                        value={selectedLegislator?.externalId}
                        onChange={handleChangeLegislator}
                    >
                        {legislators?.map((l) => {
                            return (
                                <option key={l.externalId} value={l.externalId}>
                                    {l.title} {l.fullName}
                                </option>
                            );
                        })}
                    </Form.Control>
                </Form.Group>
            )} */}
                        {render}
                    </Modal.Body>
                    <Modal.Footer>
                        <Button onClick={handleClose} variant="secondary">
                            <FiX />
                            &nbsp;<span className="align-text-top">Cancel</span>
                        </Button>
                        <Button type="submit" variant="primary">
                            {type === "phone" ? <FiPhoneCall /> : <FiMail />}
                            &nbsp;
                            <span className="align-text-top">{type === "phone" ? "Call" : "Send"}</span>
                        </Button>
                    </Modal.Footer>
                </Form>
            </Formik>
        </Modal>
    );
};

export default ContactLegislatorDialog;
