/** @format */

import {
    Button,
    createStyles,
    makeStyles,
    TextField,
    Typography,
} from "@material-ui/core";
import { Clear, Send } from "@material-ui/icons";
import { titleize } from "@sway/utils";
import { Field, Form, Formik } from "formik";
import React from "react";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import CenteredDivRow from "../shared/CenteredDivRow";

interface IProps {
    user: sway.IUser;
    legislator: sway.ILegislator;
    userVote?: sway.IUserVote;
    handleSubmit: ({ message }: { message: string }) => void;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
    methods: {
        [key: string]: () => string;
    };
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
            marginRight: 5,
            textDecoration: "none",
            color: SWAY_COLORS.primary,
        },
    }),
);

const EmailLegislatorForm: React.FC<IProps> = ({
    user,
    legislator,
    userVote,
    handleSubmit,
    handleClose,
    methods,
}) => {
    const classes = useStyles();

    return (
        <Formik
            initialValues={{ message: methods.defaultMessage() }}
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
                                <Typography component={"span"}>
                                    <Typography
                                        component={"span"}
                                        className={classes.previewHeader}
                                    >
                                        {"To: "}
                                    </Typography>
                                    <Typography component={"span"}>
                                        {methods.legislatorEmailPreview()}
                                    </Typography>
                                    <Typography
                                        component={"span"}
                                        onClick={methods.handleCopy}
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
                                            src={"/copy.svg"}
                                            className={
                                                "legislator-card-copy-icon"
                                            }
                                        />
                                    </Typography>
                                </Typography>
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
                                    <Typography
                                        component={"span"}
                                    >{`Hello ${methods.getLegislatorTitle()} ${
                                        legislator.last_name
                                    }`}</Typography>
                                </Typography>
                                {userVote && <Typography component={"span"}>
                                    <Typography
                                        component={"span"}
                                        className={classes.previewHeader}
                                    >
                                        {"Title: "}
                                    </Typography>
                                    <Typography component={"span"}>{`${titleize(
                                        methods.shortSupport(),
                                    )} bill ${
                                        userVote.billFirestoreId
                                    }`}</Typography>
                                </Typography>}
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

export default EmailLegislatorForm;
