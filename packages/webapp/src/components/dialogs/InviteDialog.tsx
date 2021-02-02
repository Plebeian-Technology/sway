/** @format */

import {
    createStyles,
    Divider,
    IconButton,
    makeStyles,
    TextField,
    Tooltip,
    Typography,
    useTheme,
} from "@material-ui/core";
import Button from "@material-ui/core/Button";
import Dialog from "@material-ui/core/Dialog";
import DialogActions from "@material-ui/core/DialogActions";
import DialogContent from "@material-ui/core/DialogContent";
import DialogContentText from "@material-ui/core/DialogContentText";
import DialogTitle from "@material-ui/core/DialogTitle";
import { Send } from "@material-ui/icons";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { get } from "@sway/utils";
import copy from "copy-to-clipboard";
import { Field, FieldArray, Form, Formik, FormikProps } from "formik";
import React, { useState } from "react";
import { sway } from "sway";
import * as yup from "yup";
import { functions } from "../../firebase";
import { handleError, notify, SWAY_COLORS } from "../../utils";
import CenteredLoading from "./CenteredLoading";

const VALIDATION_SCHEMA = yup.object().shape({
    emails: yup.array().of(yup.string().email()),
});

interface IProps {
    user: sway.IUser;
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
}

const useStyles = makeStyles(() =>
    createStyles({
        copyGroup: {
            cursor: "pointer",
        },
        copyIconContainer: {
            cursor: "pointer",
            textAlign: "center",
            fontSize: "1.5em",
        },
        copyIcon: {
            maxHeight: "1.5em",
        },
    }),
);

const InviteDialog: React.FC<IProps> = ({ user, open, handleClose }) => {
    const classes = useStyles();
    const theme = useTheme();
    const [isSendingInvites, setIsSendingInvites] = useState<boolean>(false);

    const link = `https://${process.env.REACT_APP_ORIGIN}/invite/${user.uid}`;

    const handleCopy = (value: string) => {
        copy(value, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied!",
                    message: `Copied link to clipboard`,
                    duration: 3000,
                }),
        });
    };

    const handleSubmit = (values: { emails: string[] }) => {
        const { emails } = values;
        console.log("submitting emails", emails);
        const setter = functions.httpsCallable(CLOUD_FUNCTIONS.sendUserInvites);
        setIsSendingInvites(true);
        return setter({
            emails,
            sender: user,
            locale: user.locales[0],
        })
            .then((res: firebase.default.functions.HttpsCallableResult) => {
                setIsSendingInvites(false);
                if (res.data) {
                    notify({
                        level: "error",
                        title: "Failed to send invites.",
                        message: res.data,
                        duration: 3000,
                    });
                } else {
                    notify({
                        level: "success",
                        title: "Invites sent!",
                        message: "",
                        duration: 3000,
                    });
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
                setIsSendingInvites(false);
            });
    };

    const formik = ({
        values,
        errors,
        touched,
        setFieldTouched,
        setFieldValue,
    }: FormikProps<{ emails: string[] }>) => {
        return (
            <Form>
                <FieldArray
                    name="emails"
                    render={(arrayHelpers) => (
                        <div>
                            {values.emails && values.emails.length > 0 ? (
                                values.emails.map(
                                    (email: string, index: number) => {
                                        return (
                                            <Field
                                                key={index}
                                                className={"invite-email"}
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
                                                        event?.target?.value,
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
                                    style={{ fontSize: 30, fontWeight: "bold" }}
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
                                                values.emails.length - 1,
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
                                <IconButton type={"submit"} color={"primary"}>
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
                                : `There is an issue with email ${i + 1}.`}
                        </Typography>
                    ))}
            </Form>
        );
    };

    return (
        <Dialog
            open={open}
            onClose={() => handleClose(false)}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <DialogTitle id="alert-dialog-title">
                {"Invite friends through email or a link."}
            </DialogTitle>
            <DialogContent style={{ cursor: "pointer" }}>
                <Typography
                    style={{ marginBottom: theme.spacing(2) }}
                    variant={"body1"}
                    component={"p"}
                >
                    The more friends you invite, the greater your sway.
                </Typography>
                {isSendingInvites && (
                    <CenteredLoading style={{ margin: "5px auto" }} />
                )}
                <Divider />
                <Formik
                    initialValues={{ emails: [""] }}
                    onSubmit={handleSubmit}
                    validationSchema={VALIDATION_SCHEMA}
                >
                    {formik}
                </Formik>
                <DialogContentText
                    style={{ marginTop: theme.spacing(2) }}
                    onClick={() => handleCopy(link)}
                >
                    {"Or invite your friends using this link:"}
                </DialogContentText>
                <DialogContentText
                    style={{ marginTop: theme.spacing(2) }}
                    onClick={() => handleCopy(link)}
                >
                    {link}
                </DialogContentText>
                <Tooltip
                    title="Copy Link"
                    placement="right"
                    onClick={() => handleCopy(link)}
                >
                    <div
                        className={classes.copyIconContainer}
                        onClick={() => handleCopy(link)}
                    >
                        <img
                            alt={"copy button"}
                            src={"/copy.png"}
                            className={classes.copyIcon}
                        />
                    </div>
                </Tooltip>
            </DialogContent>
            <DialogActions>
                <Button onClick={handleClose} color="primary">
                    Close
                </Button>
            </DialogActions>
        </Dialog>
    );
};

export default InviteDialog;
