/** @format */

import { EXECUTIVE_BRANCH_TITLES, IS_DEVELOPMENT, Support } from "app/frontend/sway_constants";
import { getFullUserAddress, isAtLargeLegislator, logDev, notify, titleize } from "app/frontend/sway_utils";
import copy from "copy-to-clipboard";
import { useCallback, useMemo } from "react";
import { Button, Form, Modal } from "react-bootstrap";
import { FiMail, FiPhoneCall, FiX } from "react-icons/fi";
import { sway } from "sway";
import { useLocale } from "../../hooks/useLocales";
import { useUser } from "../../hooks/users/useUser";

import FormContext from "app/frontend/components/contexts/FormContext";
import { formatPhone } from "app/frontend/sway_utils/phone";
import { useInertiaForm } from "use-inertia-form";
import ContactLegislatorForm from "../forms/ContactLegislatorForm";

interface IProps {
    user_vote?: sway.IUserVote;
    legislator: sway.ILegislator;
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
    type: "email" | "phone";
}

const ContactLegislatorDialog: React.FC<IProps> = ({ user_vote, legislator, open, handleClose, type }) => {
    const user = useUser();
    const [locale] = useLocale();

    const setClosed = useCallback(() => {
        handleClose(false);
    }, [handleClose]);

    const address = useCallback((): string => {
        return getFullUserAddress(user);
    }, [user]);

    const registeredVoter = useCallback((): string => {
        if (!user.is_registered_to_vote) {
            return "I";
        }
        return "I am registered to vote and";
    }, [user.is_registered_to_vote]);

    const shortSupport = useCallback((): string => {
        if (!user_vote) return "";

        if (user_vote.support === Support.For) {
            return "support";
        }
        return "oppose";
    }, [user_vote]);

    const longSupport = useCallback((): string => {
        if (!user_vote) return "";

        if (EXECUTIVE_BRANCH_TITLES.includes(legislator.title.toLowerCase())) {
            return shortSupport();
        }
        if (user_vote.support === Support.For) {
            return "vote in support of";
        }
        return `vote ${Support.Against}`;
    }, [legislator.title, shortSupport, user_vote]);

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

    const user_voteText = useMemo(
        () =>
            user_vote
                ? `Please ${longSupport()} bill ${user_vote.bill.external_id}.\n\r`
                : `I am ${
                      type === "phone" ? "calling" : "writing"
                  } to you today because I would like you to support... {NAME OF BILL}.\n\r`,
        [longSupport, type, user_vote],
    );

    const defaultMessage = useMemo(() => {
        return `Hello ${getLegislatorTitle()} ${legislator.last_name}, my name is {YOUR NAME} and ${registeredVoter()} reside ${residence()} at {YOUR ADDRESS}.\n\r${user_voteText} Thank you, {YOUR NAME}`;
    }, [getLegislatorTitle, legislator.last_name, registeredVoter, residence, user_voteText]);
    const defaultValues = useMemo(() => ({ message: defaultMessage }), [defaultMessage]);

    const form = useInertiaForm(defaultValues);

    const onSubmit = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();

            if (type === "email") {
                window.location.href = `mailto:${legislator.email}?subject=Concern Regarding Legislation&body=${form.data.message}`;
            } else {
                window.location.href = `tel:${legislator.phone}`;
            }
        },
        [form.data.message, legislator.email, legislator.phone, type],
    );

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
                    id: `legislator-${legislator.id}-${type}`,
                    level: "info",
                    title: (
                        <span>
                            Copied <span className="bold text-primary">{type}</span> to clipboard.
                        </span>
                    ),
                }),
        });
        return "";
    }, [getLegislatorEmail, getLegislatorPhone, type, legislator.id]);

    const render = useMemo(() => {
        if (type === "email" && !legislator.email) {
            logDev(`missing EMAIL for ${legislator.full_name} - ${legislator.external_id}`);
            return (
                <span>
                    Unfortunately, it looks like we don't have an email address for {legislator.title}{" "}
                    {legislator.full_name} in our database.
                </span>
            );
        }
        if (type === "phone" && !legislator.phone) {
            logDev(`missing PHONE for ${legislator.full_name} - ${legislator.external_id}`);
            return (
                <span>
                    Unfortunately, it looks like we don't have a phone number for {legislator.title}{" "}
                    {legislator.full_name} in our database.
                </span>
            );
        }
        if (type === "email" && legislator.email?.startsWith("http")) {
            return (
                <div>
                    <span>
                        Unfortunately, it's not possible to email {legislator.title} {legislator.full_name} directly.
                    </span>
                    <span>You can, however, email them through their website at:</span>
                    <a target="_blank" rel="noreferrer" href={legislator.email}>
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
                user_vote={user_vote}
                methods={methods}
            />
        );
    }, [
        address,
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
        user_vote,
    ]);

    const verbing = type === "phone" ? "calling" : "emailing";

    return (
        <Modal
            centered
            show={open}
            onHide={setClosed}
            aria-labelledby="contact-legislator-dialog"
            aria-describedby="contact-legislator-dialog"
        >
            <FormContext.Provider value={form}>
                <Form onSubmit={onSubmit}>
                    <Modal.Header id="contact-legislator-dialog">
                        <Modal.Title>{`Increase your sway by ${verbing} your representatives.`}</Modal.Title>
                    </Modal.Header>
                    <Modal.Body>{render}</Modal.Body>
                    <Modal.Footer>
                        <Button onClick={handleClose} variant="secondary">
                            <FiX />
                            &nbsp;<span className="align-text-top">Cancel</span>
                        </Button>
                        <Button type="submit" variant="primary">
                            {type === "phone" ? <FiPhoneCall title="Call" /> : <FiMail title="Email" />}
                            &nbsp;
                            <span className="align-text-top">{type === "phone" ? "Call" : "Send"}</span>
                        </Button>
                    </Modal.Footer>
                </Form>
            </FormContext.Provider>
        </Modal>
    );
};

export default ContactLegislatorDialog;
