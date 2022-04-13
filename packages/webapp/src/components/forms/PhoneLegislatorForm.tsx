/** @format */
import { makeStyles } from "@mui/styles";

import { Button, Link, TextField, Typography } from "@mui/material";
import { Clear, PhoneForwarded } from "@mui/icons-material";
import { formatPhone } from "@sway/utils";
import { Field, Form, Formik } from "formik";
import React from "react";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import CenteredDivRow from "../shared/CenteredDivRow";

interface IProps {
    legislator: sway.ILegislator;
    handleSubmit: ({ message }: { message: string }) => void;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
    methods: {
        [key: string]: () => string;
    };
}

const useStyles = makeStyles({
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
});

const PhoneLegislatorForm: React.FC<IProps> = ({
    legislator,
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
                        <CenteredDivCol style={{ width: "100%", alignItems: "flex-start" }}>
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
                                onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                                    setFieldValue("message", e.target.value);
                                }}
                            />
                            <Typography variant={"h6"} style={{ fontWeight: 900 }}>
                                Preview
                            </Typography>
                            <CenteredDivCol
                                style={{
                                    alignItems: "flex-start",
                                    cursor: "auto",
                                }}
                            >
                                <Typography component={"span"}>
                                    <Typography component={"span"}>{"From: "}</Typography>
                                    <Typography component={"span"}>{"sway@sway.vote"}</Typography>
                                </Typography>
                                <CenteredDivRow>
                                    <Typography>{"To: "}</Typography>
                                    <Typography>{methods.getLegislatorPhonePreview()}</Typography>
                                    <img
                                        onClick={methods.handleCopy}
                                        style={{
                                            width: 23,
                                            height: 23,
                                            cursor: "pointer",
                                        }}
                                        alt={"Copy Phone"}
                                        src={"/copy.svg"}
                                    />
                                </CenteredDivRow>
                                <Typography>{values.message}</Typography>
                            </CenteredDivCol>
                        </CenteredDivCol>
                        <CenteredDivRow style={{ justifyContent: "space-between" }}>
                            <Button type="submit" color="primary">
                                <PhoneForwarded />{" "}
                                <Link href={`tel:${formatPhone(legislator.phone)}`}>
                                    {`Call ${formatPhone(legislator.phone)}`}
                                </Link>
                            </Button>
                            <Button onClick={handleClose} color="primary">
                                <Clear />
                                <Typography>Close</Typography>
                            </Button>
                        </CenteredDivRow>
                    </Form>
                );
            }}
        </Formik>
    );
};

export default PhoneLegislatorForm;
