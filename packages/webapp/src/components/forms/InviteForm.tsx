/** @format */

import { IconButton, TextField, Typography } from "@material-ui/core";
import Button from "@material-ui/core/Button";
import { Send } from "@material-ui/icons";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { get, logDev } from "@sway/utils";
import { Field, FieldArray, Form, Formik } from "formik";
import React from "react";
import { sway } from "sway";
import * as yup from "yup";
import { functions } from "../../firebase";
import {
    GAINED_SWAY_MESSAGE,
    handleError,
    notify,
    SWAY_COLORS,
    withTadas,
} from "../../utils";

const VALIDATION_SCHEMA = yup.object().shape({
    emails: yup.array().of(yup.string().email()),
});

interface IProps {
    user: sway.IUser;
    setIsSendingInvites: (isSending: boolean) => void;
}

const InviteForm: React.FC<IProps> = ({ user, setIsSendingInvites }) => {
    const handleSubmit = (values: { emails: string[] }) => {
        const { emails } = values;
        const setter = functions.httpsCallable(CLOUD_FUNCTIONS.sendUserInvites);

        setIsSendingInvites(true);
        return setter({
            emails,
            sender: user,
            locale: user.locales[0],
        })
            .then((res: firebase.default.functions.HttpsCallableResult) => {
                setIsSendingInvites(false);
                logDev(
                    "Return data from sending user invites function.",
                    res.data,
                );
                if (res.data) {
                    console.log(res.data);

                    notify({
                        level: "error",
                        title: "Failed to send invites.",
                        message: res.data,
                    });
                } else {
                    notify({
                        level: "success",
                        title: "Invites sent!",
                        message: withTadas(GAINED_SWAY_MESSAGE),
                        tada: true,
                    });
                }
            })
            .catch((error) => {
                notify({
                    level: "error",
                    message: "Failed to send invites.",
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
            {({ values, touched, errors, setFieldValue, setFieldTouched }) => {
                return (
                    <Form>
                        <FieldArray
                            name="emails"
                            render={(arrayHelpers) => (
                                <div>
                                    {values.emails &&
                                    values.emails.length > 0 ? (
                                        values.emails.map(
                                            (email: string, index: number) => {
                                                return (
                                                    <Field
                                                        key={index}
                                                        className={
                                                            "invite-email"
                                                        }
                                                        variant={"outlined"}
                                                        placeholder={"email"}
                                                        name={`emails.${index}`}
                                                        onBlur={() => {
                                                            setFieldTouched(
                                                                `emails.${index}`,
                                                            );
                                                        }}
                                                        onChange={(
                                                            event: React.ChangeEvent<HTMLInputElement>,
                                                        ) => {
                                                            setFieldValue(
                                                                `emails.${index}`,
                                                                event?.target
                                                                    ?.value,
                                                            );
                                                        }}
                                                        type="email"
                                                        inputProps={{
                                                            style: {
                                                                color:
                                                                    SWAY_COLORS.black,
                                                            },
                                                        }}
                                                        InputProps={{
                                                            style: {
                                                                color:
                                                                    SWAY_COLORS.black,
                                                            },
                                                        }}
                                                        component={TextField}
                                                    />
                                                );
                                            },
                                        )
                                    ) : (
                                        <Button
                                            style={{
                                                fontSize: 30,
                                                fontWeight: "bold",
                                            }}
                                            type="button"
                                            onClick={() =>
                                                arrayHelpers.insert(
                                                    values.emails.length,
                                                    "",
                                                )
                                            }
                                        >
                                            Add an email
                                        </Button>
                                    )}
                                    <div className="invite-buttons">
                                        <div>
                                            <Button
                                                style={{
                                                    fontSize: 30,
                                                    fontWeight: "bold",
                                                }}
                                                type="button"
                                                onClick={() =>
                                                    arrayHelpers.remove(
                                                        values.emails.length -
                                                            1,
                                                    )
                                                }
                                            >
                                                -
                                            </Button>
                                            <Button
                                                style={{
                                                    fontSize: 30,
                                                    fontWeight: "bold",
                                                }}
                                                type="button"
                                                onClick={() =>
                                                    arrayHelpers.insert(
                                                        values.emails.length,
                                                        "",
                                                    )
                                                }
                                            >
                                                +
                                            </Button>
                                        </div>
                                        <IconButton
                                            type={"submit"}
                                            color={"primary"}
                                        >
                                            <Send />
                                        </IconButton>
                                    </div>
                                </div>
                            )}
                        />
                        {Array.isArray(errors.emails) &&
                            errors.emails.map((e: string, i: number) => (
                                <Typography key={i} color={"error"}>
                                    {!e || !get(touched, `emails.${i}`)
                                        ? ""
                                        : `There is an issue with email ${
                                              i + 1
                                          }.`}
                                </Typography>
                            ))}
                    </Form>
                );
            }}
        </Formik>
    );
};

export default InviteForm;
