import { router, usePage } from "@inertiajs/react";
import FormContext from "app/frontend/components/contexts/FormContext";
import { useContactLegislator } from "app/frontend/components/forms/useContactLegislator";
import { useAxios_NOT_Authenticated_GET } from "app/frontend/hooks/useAxios";
import { useUser } from "app/frontend/hooks/users/useUser";
import { notify } from "app/frontend/sway_utils";
import { useCallback, useMemo, useState } from "react";
import { Button, Form, Modal } from "react-bootstrap";
import { FiMail, FiSend } from "react-icons/fi";
import { sway } from "sway";
import { useInertiaForm } from "use-inertia-form";

const CONFIRMATION_ROUTE = "/email_verification";
const VERIFICATION_ROUTE = "/email_verification/0";
const RESET_ROUTE = "/email_verification/0";
const USER_DETAILS_ROUTE = "/users/details";
const USER_LEGISLATOR_EMAIL_ROUTE = "/user_legislator_emails";

const UserLegislatorEmailForm = () => {
    const user = useUser();
    const bill = usePage().props.bill as sway.IBill;
    const user_vote = usePage().props.user_vote as sway.IUserVote;
    const legislator = usePage().props.legislator as sway.ILegislator | undefined;
    const contact = useContactLegislator(legislator, user_vote, "email");

    const emailConfirmationForm = useInertiaForm<{ email: string; bill_id: number }>({
        email: user.email ?? "",
        bill_id: bill.id,
    });
    const emailVerificationForm = useInertiaForm<{ code: string; bill_id: number }>({
        code: "",
        bill_id: bill.id,
    });
    const userDetailsForm = useInertiaForm<{ full_name: string | undefined; bill_id: number }>({
        full_name: user.full_name ?? "",
        bill_id: bill.id,
    });
    const userLegislatorEmailForm = useInertiaForm<{ bill_id: number }>({
        bill_id: bill.id,
    });
    const isNeedsUserDetails = useMemo(() => !user.full_name, [user.full_name]);

    const activeForm = useMemo(() => {
        if (!user.email) {
            return emailConfirmationForm;
        } else if (!user.is_email_verified) {
            return emailVerificationForm;
        } else if (!user.full_name) {
            return userDetailsForm;
        } else {
            return userLegislatorEmailForm;
        }
    }, [
        emailConfirmationForm,
        emailVerificationForm,
        user.email,
        user.full_name,
        user.is_email_verified,
        userDetailsForm,
        userLegislatorEmailForm,
    ]);

    const [isOpen, setOpen] = useState<boolean>(window.location.search.includes("with"));
    const handleClose = useCallback(() => setOpen(false), []);
    const handleOpen = useCallback(() => {
        router.visit(window.location.pathname, {
            preserveScroll: true,
            preserveState: true,
            data: {
                with: "legislator,address",
            },
            onFinish: () => {
                setOpen(true);
            },
        });
    }, []);

    const onSubmit = useCallback((method: (url: string, options?: any) => void, route: string) => {
        method(route, {
            async: false,
            preserveScroll: true,
            preserveState: route !== USER_LEGISLATOR_EMAIL_ROUTE,
            onSuccess: () => {
                if (route === USER_LEGISLATOR_EMAIL_ROUTE) {
                    notify({
                        level: "success",
                        title: "Sending emails to your representatives. You will be CC'ed on them.",
                    });
                } else {
                    router.visit(window.location.pathname, {
                        only: ["user"],
                        preserveScroll: true,
                        preserveState: true,
                        data: {
                            with: "legislator,address",
                        },
                    });
                }
            },
            onError: () => {
                switch (route) {
                    case CONFIRMATION_ROUTE:
                        notify({
                            level: "error",
                            title: "There was an error sending a verification email. Please try again.",
                        });
                        break;
                    case VERIFICATION_ROUTE:
                        notify({
                            level: "error",
                            title: "There was an error verifying your email. Please try again.",
                        });
                        break;
                    case USER_DETAILS_ROUTE:
                        notify({
                            level: "error",
                            title: "There was an error saving your details. Please try again.",
                        });
                        break;
                    case USER_LEGISLATOR_EMAIL_ROUTE:
                        notify({
                            level: "error",
                            title: "There was an error sending emails to your representatives. Please try again.",
                        });
                        break;
                    default:
                        break;
                }
            },
        });
    }, []);

    const { get: reset } = useAxios_NOT_Authenticated_GET(RESET_ROUTE, { method: "delete", skipInitialRequest: true });
    const onReset = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            e.stopPropagation();

            reset()
                .then(() => {
                    router.visit(window.location.pathname, {
                        only: ["user"],
                        preserveScroll: true,
                        preserveState: true,
                        data: {
                            with: "legislator,address",
                        },
                    });
                })
                .catch((error) => {
                    console.error(error);
                    notify({ level: "error", title: "Failed to reset verification. Please try again." });
                });
        },
        [reset],
    );

    const onSubmitConfirm = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            e.stopPropagation();
            onSubmit(emailConfirmationForm.post, CONFIRMATION_ROUTE);
        },
        [emailConfirmationForm.post, onSubmit],
    );

    const onSubmitVerify = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            e.stopPropagation();
            onSubmit(emailVerificationForm.put, VERIFICATION_ROUTE);
        },
        [emailVerificationForm.put, onSubmit],
    );

    const onSubmitUserDetails = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            e.stopPropagation();
            onSubmit(userDetailsForm.post, USER_DETAILS_ROUTE);
        },
        [onSubmit, userDetailsForm],
    );

    const onSubmitMessage = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            e.stopPropagation();
            onSubmit(userLegislatorEmailForm.post, USER_LEGISLATOR_EMAIL_ROUTE);
        },
        [onSubmit, userLegislatorEmailForm],
    );

    const handler = useMemo(() => {
        if (!user.email) {
            return onSubmitConfirm;
        } else if (!user.is_email_verified) {
            return onSubmitVerify;
        } else if (isNeedsUserDetails) {
            return onSubmitUserDetails;
        } else {
            return onSubmitMessage;
        }
    }, [
        isNeedsUserDetails,
        onSubmitConfirm,
        onSubmitMessage,
        onSubmitUserDetails,
        onSubmitVerify,
        user.email,
        user.is_email_verified,
    ]);

    const action = useMemo(() => {
        if (!user.email || isNeedsUserDetails) {
            return "Submit";
        } else if (!user.is_email_verified) {
            return "Verify";
        } else {
            return (
                <>
                    Send&nbsp;
                    <FiSend />
                </>
            );
        }
    }, [isNeedsUserDetails, user.email, user.is_email_verified]);

    const title = useMemo(() => {
        if (!user.email) {
            return "What's Your Email?";
        } else if (!user.is_email_verified) {
            return "Verify Your Email";
        } else if (isNeedsUserDetails) {
            return "Your Details";
        } else {
            return "Message Your Legislators";
        }
    }, [isNeedsUserDetails, user.email, user.is_email_verified]);

    const body = useMemo(() => {
        if (!user.email || !user.is_email_verified) {
            return (
                <Form.Group className="col">
                    <Form.Label>
                        <p>
                            In order to email your representatives, Sway needs your email address. For now it{" "}
                            <span className="bold">cannot be changed</span> so please make sure to enter it accurately.
                        </p>
                        {user.email && <p>Please verify your email by entering the code we just sent you</p>}
                    </Form.Label>
                    {user.email ? (
                        <Form.FloatingLabel label="Code:">
                            <Form.Control
                                maxLength={6}
                                type="text"
                                name="code"
                                autoComplete="one-time-code"
                                value={emailVerificationForm.data.code}
                                onChange={(e) => emailVerificationForm.setData("code", e.target.value)}
                                disabled={emailConfirmationForm.processing || emailVerificationForm.processing}
                            />
                        </Form.FloatingLabel>
                    ) : (
                        <Form.FloatingLabel label="Email:">
                            <Form.Control
                                type="email"
                                name="email"
                                autoComplete="email"
                                value={emailConfirmationForm.data.email}
                                onChange={(e) => emailConfirmationForm.setData("email", e.target.value)}
                                disabled={emailConfirmationForm.processing || emailVerificationForm.processing}
                            />
                        </Form.FloatingLabel>
                    )}
                </Form.Group>
            );
        } else if (isNeedsUserDetails) {
            return (
                <div className="col">
                    <p>Sway needs your name and address to give your representatives more details about you.</p>
                    <Form.FloatingLabel label="Full Name:">
                        <Form.Control
                            maxLength={100}
                            type="text"
                            name="full_name"
                            autoComplete="name"
                            value={userDetailsForm.data.full_name}
                            onChange={(e) => userDetailsForm.setData("full_name", e.target.value)}
                            disabled={userDetailsForm.processing}
                        />
                    </Form.FloatingLabel>
                </div>
            );
        } else if (contact && legislator) {
            return (
                <div className="col">
                    <p>
                        Sway can send an email to each your representatives expressing your{" "}
                        {user_vote.support === "FOR" ? "support of" : "opposition to"} this legislation.
                    </p>
                    <p>Below is an example of the email message that each will receive:</p>
                    <p className="p-3 bg-light fw-normal">
                        Hello {contact.getLegislatorTitle()} {legislator.last_name}, my name is{" "}
                        {user.full_name ?? "{YOUR_NAME}"} and {contact.registeredVoter()} reside {contact.residence()}
                        {contact.fullAddress() ? " at " + contact.fullAddress() : ""}.
                        <br />
                        <br />
                        {contact.userVoteText()}
                        <br />
                        <br />
                        Thank you, {user.full_name ?? "{YOUR_NAME}"}
                    </p>
                </div>
            );
        } else {
            return null;
        }
    }, [
        contact,
        emailConfirmationForm,
        emailVerificationForm,
        isNeedsUserDetails,
        legislator,
        user.email,
        user.full_name,
        user.is_email_verified,
        userDetailsForm,
        user_vote.support,
    ]);

    return (
        <>
            <Button variant="outline-primary" size="lg" onClick={handleOpen} style={{ flex: 1 }}>
                <FiMail />
                &nbsp;Email Legislators
            </Button>
            <Modal centered show={isOpen} aria-labelledby="share-buttons-dialog" onHide={handleClose}>
                <FormContext.Provider value={activeForm}>
                    <Form onSubmit={handler}>
                        <Modal.Header>
                            <Modal.Title id="email-legislators-modal-title">{title}</Modal.Title>
                        </Modal.Header>
                        <Modal.Body>{body}</Modal.Body>
                        <Modal.Footer>
                            {user.email && !user.is_email_verified && (
                                <Button variant="outline-primary" onClick={onReset}>
                                    Start Over
                                </Button>
                            )}
                            <Button type="submit">{action}</Button>
                        </Modal.Footer>
                    </Form>
                </FormContext.Provider>
            </Modal>
        </>
    );
};

export default UserLegislatorEmailForm;
