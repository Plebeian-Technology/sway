import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { titleize } from "app/frontend/sway_utils";
import { Form } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    legislator: sway.ILegislator;
    user_vote?: sway.IUserVote;
    type: "email" | "phone";
    methods: {
        [key: string]: () => string;
    };
}

const ContactLegislatorFormEditable: React.FC<IProps> = ({ user, legislator, user_vote, type, methods }) => {
    const { data, setData } = useFormContext<{ message: string }>();

    return (
        <div className="row">
            <div className="col">
                <Form.Group controlId="message" className="my-2">
                    <Form.Label>Message:</Form.Label>
                    <Form.Control
                        rows={10}
                        name="message"
                        as="textarea"
                        value={data.message}
                        onChange={(e) => setData("message", e.target.value)}
                    />
                </Form.Group>
                <hr />
                <div className="bold mt-3">Preview:</div>
                <div className="col">
                    {type === "email" && (
                        <>
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
                                    <FiCopy title="Copy" onClick={methods.handleCopy} />
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
                        </>
                    )}
                    {user_vote ? (
                        <div className="row">
                            <div className="col">
                                <span className="bold">{type === "email" ? "Title: " : "Regarding: "}</span>
                                <span>{`${titleize(methods.shortSupport())} bill ${user_vote.bill.external_id}`}</span>
                            </div>
                        </div>
                    ) : (
                        <div className="row">
                            <div className="col">
                                <span className="bold">{type === "email" ? "Title: " : "Regarding: "}</span>
                                <span>{`Hello ${methods.getLegislatorTitle()} ${legislator.last_name}`}</span>
                            </div>
                        </div>
                    )}
                    <div className="row my-2">
                        <div className="col">{data.message}</div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default ContactLegislatorFormEditable;
