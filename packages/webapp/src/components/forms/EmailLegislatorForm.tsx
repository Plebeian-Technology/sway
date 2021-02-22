/** @format */

import { Button, createStyles, makeStyles, TextField } from "@material-ui/core";
import { Clear, Send } from "@material-ui/icons";
import { IS_DEVELOPMENT, titleize } from "@sway/utils";
import copy from "copy-to-clipboard";
import { Field, Form, Formik } from "formik";
import React from "react";
import { sway } from "sway";
import { notify, SWAY_COLORS } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import CenteredDivRow from "../shared/CenteredDivRow";

interface IProps {
    user: sway.IUser;
    legislator: sway.ILegislator;
    handleSubmit: ({ message }: { message: string }) => void;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
}

const useStyles = makeStyles(() =>
    createStyles({
        previewHeader: {
            fontWeight: 500,
        },
        preview: {
            border: `2px solid ${SWAY_COLORS.secondaryDark}`,
            margin: 10,
            padding: 10,
            whiteSpace: "pre-wrap",
        },
    }),
);

const EmailLegislatorForm: React.FC<IProps> = ({
    user,
    legislator,
    handleSubmit,
    handleClose,
}) => {
    const classes = useStyles();

    const address = () => {
        const address2 = user.address2;
        if (address2) {
            return `${user.address1}, ${address2} ${user.city}, ${user.region} ${user.postalCode}-${user.postalCodeExtension}`;
        }
        return `${user.address1}, ${user.city}, ${user.region} ${user.postalCode}-${user.postalCodeExtension}`;
    };

    const registeredVoter = () => {
        if (!user.isRegisteredToVote) {
            return "I";
        }
        return "I am registered to vote and";
    };

    const residence = () => {
        if (legislator.district === 0) {
            return `in ${titleize(user.city)}`;
        }
        return `in your district`;
    };

    const defaultMessage = (): string =>
        `Hello ${legislator.title} ${legislator.last_name}, my name is ${
            user.name
        } and ${registeredVoter()} reside ${residence()} at ${titleize(
            address(),
        )}.\n\r\n\rI'm messaging you today because...\n\r\n\rThank you, ${user.name}`;

    const legislatorEmail = () => {
        if (IS_DEVELOPMENT) {
            return "legis@sway.vote";
        }
        return legislator.email;
    };

    const legislatorEmailPreview = () => {
        if (IS_DEVELOPMENT) {
            return `(dev) legis@sway.vote - (prod) ${legislator.email}`;
        }
        return legislator.email;
    };

    const handleCopy = () => {
        copy(legislatorEmail(), {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied!",
                    message: "Copied email to clipboard",
                    duration: 3000,
                }),
        });
    };

    return (
        <Formik
            initialValues={{ message: defaultMessage() }}
            onSubmit={handleSubmit}
            enableReinitialize={true}
        >
            {({ values, setFieldValue }) => {
                return (
                    <Form style={{ paddingBottom: 10 }}>
                        <CenteredDivCol
                            style={{ width: "100%", alignItems: "flex-start" }}
                        >
                            <Field
                                component={TextField}
                                name={"message"}
                                type={"text"}
                                fullWidth
                                multiline
                                rows={10}
                                margin={"normal"}
                                label={"Message:"}
                                variant="filled"
                                style={{ marginTop: 10 }}
                                value={values.message}
                                onChange={(
                                    e: React.ChangeEvent<HTMLInputElement>,
                                ) => {
                                    setFieldValue("message", e.target.value);
                                }}
                            />
                            <h4 style={{ fontWeight: 900 }}>Preview</h4>
                            <CenteredDivCol
                                style={{
                                    alignItems: "flex-start",
                                    cursor: "auto",
                                }}
                            >
                                <span>
                                    <span className={classes.previewHeader}>
                                        {"From: "}
                                    </span>
                                    <span>{"sway@sway.vote"}</span>
                                </span>
                                <span>
                                    <span className={classes.previewHeader}>
                                        {"To: "}
                                    </span>
                                    <span>{legislatorEmailPreview()}</span>
                                    <span
                                        onClick={handleCopy}
                                        style={{
                                            position: "relative",
                                            cursor: "pointer",
                                        }}
                                    >
                                        <img
                                            style={{
                                                position: "absolute",
                                                bottom: 2,
                                                margin: "0px 5px",
                                                width: 15,
                                                height: 15,
                                            }}
                                            alt={"copy button"}
                                            src={"/copy.png"}
                                            className={
                                                "legislator-card-copy-icon"
                                            }
                                        />
                                    </span>
                                </span>
                                <span>
                                    <span className={classes.previewHeader}>
                                        {"CC: "}
                                    </span>
                                    <span>{user.email}</span>
                                </span>
                                <span>
                                    <span className={classes.previewHeader}>
                                        {"ReplyTo: "}
                                    </span>
                                    <span>{user.email}</span>
                                </span>
                                <span>
                                    <span className={classes.previewHeader}>
                                        {"Title: "}
                                    </span>
                                    <span>{`Hello ${legislator.full_name}`}</span>
                                </span>
                                <p className={classes.preview}>
                                    {values.message}
                                </p>
                            </CenteredDivCol>
                        </CenteredDivCol>
                        <CenteredDivRow
                            style={{ justifyContent: "space-between" }}
                        >
                            <Button type="submit" color="primary">
                                <Send />
                                <span
                                    style={{ fontWeight: 900, marginRight: 5 }}
                                >
                                    Send
                                </span>
                            </Button>
                            <Button onClick={handleClose} color="primary">
                                <Clear />
                                <span
                                    style={{ fontWeight: 900, marginRight: 5, paddingTop: 1 }}
                                >
                                    Close
                                </span>
                            </Button>
                        </CenteredDivRow>
                    </Form>
                );
            }}
        </Formik>
    );
};

export default EmailLegislatorForm;
