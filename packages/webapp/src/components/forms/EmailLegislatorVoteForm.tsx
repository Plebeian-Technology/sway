/** @format */

import copy from "copy-to-clipboard";
import {
    Button,
    createStyles,
    makeStyles,
    TextField,
    Typography,
} from "@material-ui/core";
import { Clear, Send } from "@material-ui/icons";
import { EXECUTIVE_BRANCH_TITLES, Support } from "@sway/constants";
import { isAtLargeLegislator, IS_DEVELOPMENT, titleize } from "@sway/utils";
import { Field, Form, Formik } from "formik";
import React from "react";
import { sway } from "sway";
import { notify, SWAY_COLORS } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import CenteredDivRow from "../shared/CenteredDivRow";

interface IProps {
    user: sway.IUser;
    legislator: sway.ILegislator;
    userVote: sway.IUserVote;
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
        footerText: {
            fontWeight: 900,
            marginLeft: 5,
            paddingTop: 1,
        },
    }),
);

const EmailLegislatorVoteForm: React.FC<IProps> = ({
    user,
    legislator,
    userVote,
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

    const shortSupport = () => {
        if (userVote.support === Support.For) {
            return "support";
        }
        return "oppose";
    };

    const longSupport = () => {
        if (EXECUTIVE_BRANCH_TITLES.includes(legislator.title.toLowerCase())) {
            return shortSupport();
        }
        if (userVote.support === Support.For) {
            return "vote in support of";
        }
        return `vote ${Support.Against}`;
    };

    const residence = () => {
        if (isAtLargeLegislator(legislator)) {
            return `in ${titleize(user.city)}`;
        }
        return `in your district`;
    };

    const _legislatorTitle = (title: string) => {
        if (title?.toLowerCase() === "councilmember") {
            return "Council Member";
        }
        return title;
    };

    const defaultMessage = (): string =>
        `Hello ${_legislatorTitle(legislator.title)} ${
            legislator.last_name
        }, my name is ${
            user.name
        } and ${registeredVoter()} reside ${residence()} at ${titleize(
            address(),
        )}.\n\r\n\rPlease ${longSupport()} bill ${
            userVote.billFirestoreId
        }.\n\r\n\rThank you, ${user.name}`;

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
                            <Typography
                                variant={"h6"}
                                style={{ fontWeight: 900 }}
                            >
                                Preview
                            </Typography>
                            <CenteredDivCol
                                style={{
                                    alignItems: "flex-start",
                                    cursor: "auto",
                                }}
                            >
                                <Typography component={"span"}>
                                    <Typography
                                        component={"span"}
                                        className={classes.previewHeader}
                                    >
                                        {"From: "}
                                    </Typography>
                                    <Typography component={"span"}>
                                        {"sway@sway.vote"}
                                    </Typography>
                                </Typography>
                                <CenteredDivRow>
                                    <Typography
                                        component={"span"}
                                        className={classes.previewHeader}
                                    >
                                        {"To: "}
                                    </Typography>
                                    <Typography component={"span"}>
                                        {legislatorEmailPreview()}
                                    </Typography>
                                    <img
                                        onClick={handleCopy}
                                        style={{
                                            width: 23,
                                            height: 23,
                                            cursor: "pointer",
                                        }}
                                        alt={"Copy Email"}
                                        src={"/copy.svg"}
                                        className={"legislator-card-copy-icon"}
                                    />
                                </CenteredDivRow>
                                <Typography component={"span"}>
                                    <Typography
                                        component={"span"}
                                        className={classes.previewHeader}
                                    >
                                        {"CC: "}
                                    </Typography>
                                    <Typography component={"span"}>
                                        {user.email}
                                    </Typography>
                                </Typography>
                                <Typography component={"span"}>
                                    <Typography
                                        component={"span"}
                                        className={classes.previewHeader}
                                    >
                                        {"ReplyTo: "}
                                    </Typography>
                                    <Typography component={"span"}>
                                        {user.email}
                                    </Typography>
                                </Typography>
                                <Typography component={"span"}>
                                    <Typography
                                        component={"span"}
                                        className={classes.previewHeader}
                                    >
                                        {"Title: "}
                                    </Typography>
                                    <Typography component={"span"}>{`${titleize(
                                        shortSupport(),
                                    )} bill ${
                                        userVote.billFirestoreId
                                    }`}</Typography>
                                </Typography>
                                <Typography
                                    component={"span"}
                                    className={classes.preview}
                                >
                                    {values.message}
                                </Typography>
                            </CenteredDivCol>
                        </CenteredDivCol>
                        <CenteredDivRow
                            style={{ justifyContent: "space-between" }}
                        >
                            <Button type="submit" color="primary">
                                <Send />
                                <Typography className={classes.footerText}>
                                    Send
                                </Typography>
                            </Button>
                            <Button onClick={handleClose} color="primary">
                                <Clear />
                                <Typography className={classes.footerText}>
                                    Close
                                </Typography>
                            </Button>
                        </CenteredDivRow>
                    </Form>
                );
            }}
        </Formik>
    );
};

export default EmailLegislatorVoteForm;
