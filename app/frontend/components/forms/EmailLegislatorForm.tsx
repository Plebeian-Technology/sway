/** @format */

import { titleize } from "@sway/utils";
import { useFormikContext } from "formik";
import { Form } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    legislator: sway.ILegislator;
    userVote?: sway.IUserVote;
    type: "email" | "phone";
    legislators: sway.ILegislator[];
    selectedLegislator: sway.ILegislator;
    handleChangeLegislator: (event: React.ChangeEvent<{ value: unknown }>) => void;
    methods: {
        [key: string]: () => string;
    };
}

const EmailLegislatorForm: React.FC<IProps> = ({
    user,
    legislator,
    userVote,
    methods,
    type,
    legislators,
    selectedLegislator,
    handleChangeLegislator,
}) => {
    const { values, handleChange } = useFormikContext<{ message: string }>();

    const verbing = type === "phone" ? "calling" : "emailing";

    return (
        <>
            <span>Don't know what to say? Here's an editable prompt for you.</span>
            {legislators.length > 0 && (
                <Form.Group controlId="legislator" className="my-2">
                    <Form.Label>{titleize(verbing)}:</Form.Label>
                    <Form.Control
                        as="select"
                        name="legislator"
                        value={selectedLegislator?.externalId}
                        onChange={handleChangeLegislator}
                    >
                        {legislators?.map((l) => {
                            return (
                                <option key={l.externalId} value={l.externalId}>
                                    {l.title} {l.full_name}
                                </option>
                            );
                        })}
                    </Form.Control>
                </Form.Group>
            )}
            <div className="row">
                <div className="col">
                    <Form.Group controlId="message" className="my-2">
                        <Form.Label>Message:</Form.Label>
                        <Form.Control
                            rows={10}
                            name="message"
                            as="textarea"
                            value={values.message}
                            onChange={handleChange}
                        />
                    </Form.Group>
                    <div className="bold mt-3">Preview:</div>
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
                                <FiCopy onClick={methods.handleCopy} />
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
                                <span className="bold">{"Reply To: "}</span>
                                <span>{user.email}</span>
                            </div>
                        </div>
                        {userVote ? (
                            <div className="row">
                                <div className="col">
                                    <span className="bold">{"Title: "}</span>
                                    <span>{`${titleize(methods.shortSupport())} bill ${
                                        userVote.billFirestoreId
                                    }`}</span>
                                </div>
                            </div>
                        ) : (
                            <div className="row">
                                <div className="col">
                                    <span className="bold">{"Title: "}</span>
                                    <span>{`Hello ${methods.getLegislatorTitle()} ${
                                        legislator.last_name
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
        </>
    );
};

export default EmailLegislatorForm;
