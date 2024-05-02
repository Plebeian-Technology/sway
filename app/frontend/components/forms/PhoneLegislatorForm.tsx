/** @format */

import { titleize } from "app/frontend/sway_utils";
import { useFormikContext } from "formik";
import { Form } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";
import { sway } from "sway";

interface IProps {
    legislator: sway.ILegislator;
    type: "email" | "phone";
    legislators: sway.ILegislator[];
    selectedLegislator: sway.ILegislator;
    handleChangeLegislator: (event: React.ChangeEvent<{ value: unknown }>) => void;
    methods: {
        [key: string]: () => string;
    };
}

const PhoneLegislatorForm: React.FC<IProps> = ({
    methods,
    type,
    legislators,
    selectedLegislator,
    handleChangeLegislator,
}) => {
    const { values } = useFormikContext<{ message: string }>();

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
                                    {l.title} {l.fullName}
                                </option>
                            );
                        })}
                    </Form.Control>
                </Form.Group>
            )}
            <span className="bold">Preview</span>
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
                            <span className="bold">{methods.getLegislatorPhonePreview()}</span>
                            <FiCopy onClick={methods.handleCopy} />
                        </div>
                    </div>
                    <div className="row my-2">
                        <div className="col">
                            <span>{values.message}</span>
                        </div>
                    </div>
                </div>
            </div>
        </>
    );
};

export default PhoneLegislatorForm;
