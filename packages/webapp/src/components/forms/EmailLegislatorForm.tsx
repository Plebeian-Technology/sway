/** @format */
import { Clear, ContentCopy, Send } from "@mui/icons-material";
import { Button, TextField } from "@mui/material";
import { titleize } from "@sway/utils";
import { Field, Form, Formik } from "formik";
import React from "react";
import { sway } from "sway";

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

const EmailLegislatorForm: React.FC<IProps> = ({
    user,
    legislator,
    userVote,
    handleSubmit,
    handleClose,
    methods,
}) => {
    return (
        <Formik
            initialValues={{ message: methods.defaultMessage() }}
            onSubmit={handleSubmit}
            enableReinitialize={true}
        >
            {({ values, setFieldValue }) => {
                return (
                    <Form className="col">
                        <div className="row">
                            <div className="col">
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
                                    value={values.message}
                                    onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                                        setFieldValue("message", e.target.value);
                                    }}
                                />
                                <span className="bolder">Preview</span>
                                <div className="col">
                                    <div className="row">
                                        <div className="col">
                                            <span className="bold">{"From: "}</span>
                                            <span>{"sway@sway.vote"}</span>
                                        </div>
                                    </div>
                                    <div className="row">
                                        <div className="col">
                                            <span className="bold">{"To: "}</span>
                                            <span>{methods.getLegislatorEmailPreview()}</span>
                                            <ContentCopy onClick={methods.handleCopy} />
                                        </div>
                                    </div>
                                    <div className="row">
                                        <div className="col">
                                            <span className="bold">{"CC: "}</span>
                                            <span>{user.email}</span>
                                        </div>
                                    </div>
                                    <div className="row">
                                        <div className="col">
                                            <span className="bold">{"ReplyTo: "}</span>
                                            <span>{user.email}</span>
                                        </div>
                                    </div>
                                    <div className="row">
                                        <div className="col">
                                            <span className="bold">{"Title: "}</span>
                                            <span>{`Hello ${methods.getLegislatorTitle()} ${
                                                legislator.last_name
                                            }`}</span>
                                        </div>
                                    </div>
                                    {userVote && (
                                        <div className="row">
                                            <div className="col">
                                                <span className="bold">{"Title: "}</span>
                                                <span>{`${titleize(methods.shortSupport())} bill ${
                                                    userVote.billFirestoreId
                                                }`}</span>
                                            </div>
                                        </div>
                                    )}
                                    <div className="row my-2">
                                        <div className="col">{values.message}</div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div className="row">
                            <div className="col ps-0">
                                <Button type="submit" color="primary">
                                    <Send />
                                    &nbsp;
                                    <span>Send</span>
                                </Button>
                            </div>
                            <div className="col text-end">
                                <Button onClick={handleClose} color="primary">
                                    <Clear />
                                    &nbsp;
                                    <span>Close</span>
                                </Button>
                            </div>
                        </div>
                    </Form>
                );
            }}
        </Formik>
    );
};

export default EmailLegislatorForm;
