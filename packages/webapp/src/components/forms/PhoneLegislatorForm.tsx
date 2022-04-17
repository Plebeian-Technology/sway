/** @format */
import { Clear, ContentCopy, PhoneForwarded } from "@mui/icons-material";
import { Button, Link, TextField } from "@mui/material";
import { formatPhone } from "@sway/utils";
import { Field, Form, Formik } from "formik";
import { sway } from "sway";

interface IProps {
    legislator: sway.ILegislator;
    handleSubmit: ({ message }: { message: string }) => void;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
    methods: {
        [key: string]: () => string;
    };
}

const PhoneLegislatorForm: React.FC<IProps> = ({
    legislator,
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
                                <div className="row">
                                    <div className="col">
                                        <div className="row">
                                            <div className="col">
                                                <span>{"From: "}</span>
                                                <span className="bold">{"sway@sway.vote"}</span>
                                            </div>
                                        </div>
                                        <div className="row">
                                            <div className="col">
                                                <span>{"To: "}</span>
                                                <span className="bold">
                                                    {methods.getLegislatorPhonePreview()}
                                                </span>
                                                <ContentCopy onClick={methods.handleCopy} />
                                            </div>
                                        </div>
                                        <div className="row my-2">
                                            <div className="col">
                                                <span>{values.message}</span>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div className="row my-2">
                            <div className="col ps-0">
                                <Button type="submit" color="primary">
                                    <PhoneForwarded />
                                    &nbsp;
                                    <Link href={`tel:${formatPhone(legislator.phone)}`}>
                                        {`Call ${formatPhone(legislator.phone)}`}
                                    </Link>
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

export default PhoneLegislatorForm;
