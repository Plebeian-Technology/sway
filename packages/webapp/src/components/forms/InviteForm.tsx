/** @format */

import { CLOUD_FUNCTIONS } from "@sway/constants";
import { get, isEmptyObject, logDev } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import { FieldArray, Form, Formik } from "formik";
import { Button, Form as BootstrapForm } from "react-bootstrap";
import { FiMinus, FiPlus, FiSend } from "react-icons/fi";
import { sway } from "sway";
import * as yup from "yup";
import { functions } from "../../firebase";
import { GAINED_SWAY_MESSAGE, handleError, notify, withTadas } from "../../utils";

const VALIDATION_SCHEMA = yup.object().shape({
    emails: yup.array().of(yup.string().email()),
});

interface IProps {
    user: sway.IUser;
    setIsSendingInvites: (isSending: boolean) => void;
}

interface ISentInvitesResponseData {
    sent: string[];
    rejected: string[];
}

const InviteForm: React.FC<IProps> = ({ user, setIsSendingInvites }) => {
    const handleSubmit = (values: { emails: string[] }) => {
        const { emails } = values;
        const setter = httpsCallable(functions, CLOUD_FUNCTIONS.sendUserInvites);

        setIsSendingInvites(true);
        return setter({
            emails,
            sender: user,
            locale: user.locales[0],
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
                notify({
                    level: "error",
                    title: "Failed to send invites.",
                });
                handleError(error);
                setIsSendingInvites(false);
            });
    };

    return (
        <Formik
            initialValues={{ emails: [""] }}
            onSubmit={handleSubmit}
            validationSchema={VALIDATION_SCHEMA}
        >
            {({ values, touched, errors, setFieldTouched, handleChange }) => {
                const { emails } = values;
                return (
                    <Form>
                        <FieldArray
                            name="emails"
                            render={(arrayHelpers) => (
                                <div>
                                    {emails && emails.length > 0 ? (
                                        emails.map((email: string, index: number) => {
                                            return (
                                                <BootstrapForm.Group
                                                    key={`emails.${index}`}
                                                    controlId={`emails.${index}`}
                                                    className="my-2"
                                                >
                                                    <BootstrapForm.Control
                                                        type="email"
                                                        className="invite-email"
                                                        placeholder="Enter email..."
                                                        name={`emails.${index}`}
                                                        onChange={handleChange}
                                                        onBlur={() => {
                                                            setFieldTouched(`emails.${index}`);
                                                        }}
                                                    />
                                                </BootstrapForm.Group>
                                            );
                                        })
                                    ) : (
                                        <Button
                                            onClick={() => arrayHelpers.insert(emails.length, "")}
                                        >
                                            Add an email
                                        </Button>
                                    )}
                                    <div className="row mt-2">
                                        <div className="col-2 pe-0">
                                            <Button
                                                onClick={() =>
                                                    arrayHelpers.remove(emails.length - 1)
                                                }
                                            >
                                                <FiMinus />
                                            </Button>
                                        </div>
                                        <div className="col-2 ps-0">
                                            <Button
                                                onClick={() =>
                                                    arrayHelpers.insert(emails.length, "")
                                                }
                                            >
                                                <FiPlus />
                                            </Button>
                                        </div>
                                        <div className="col-8 text-end">
                                            <Button type="submit">
                                                <FiSend />
                                            </Button>
                                        </div>
                                    </div>
                                </div>
                            )}
                        />
                        {Array.isArray(errors.emails) &&
                            errors.emails.map((e: string, i: number) => (
                                <span key={i} color={"error"}>
                                    {!e || !get(touched, `emails.${i}`)
                                        ? ""
                                        : `There is an issue with email ${i + 1}.`}
                                </span>
                            ))}
                    </Form>
                );
            }}
        </Formik>
    );
};

export default InviteForm;
