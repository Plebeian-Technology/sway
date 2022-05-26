import { logDev } from "@sway/utils";
import { useField } from "formik";
import { useCallback, useEffect, useState } from "react";
import { Form } from "react-bootstrap";
import { handleError } from "../../../utils";
import { withEmojis } from "../../../utils/emoji";
import SwayTextArea from "../../forms/SwayTextArea";
import BillSummaryMarkdown from "../BillSummaryMarkdown";

interface IProps {
    fieldname: string;
    organizationName: string;
    isSupporting: boolean;
    setFieldValue: (fieldname: string, fieldvalue: string[] | string | boolean | null) => void;
    handleSetTouched: (fieldname: string) => void;
    error: string;
}

const BillCreatorOrganization: React.FC<IProps> = ({
    fieldname,
    organizationName,
    setFieldValue,
    handleSetTouched,
    isSupporting,
    error,
}) => {
    const positionFieldname = `${fieldname}.position`;
    const supportsFieldname = `${fieldname}.support`;
    const [formikPosition] = useField(positionFieldname);

    const [summary, setSummary] = useState<string>("");
    const handleChange = useCallback(async (_fieldname: string, fieldvalue: string) => {
        setSummary(withEmojis(fieldvalue));
    }, []);

    useEffect(() => {
        logDev("BillCreatorOrganization.useEffect - LOAD");
        const load = async () => {
            if (formikPosition.value && !summary) {
                logDev("BILL CREATOR - ORGANIZATION LOAD");
                setSummary(formikPosition.value);
            }
        };
        load().catch(handleError);
    }, []);

    useEffect(() => {
        logDev("BillCreatorOrganization.useEffect - SEND VALUE");
        const sendValue = async () => {
            setFieldValue(positionFieldname, summary);
            handleSetTouched(positionFieldname);
        };
        sendValue().catch(handleError);
    }, [summary]);

    return (
        <div className="col py-2">
            <div className="row">
                <div className="col">
                    <Form.Check
                        type="switch"
                        checked={isSupporting}
                        label={isSupporting ? "Supports" : "Opposes"}
                        onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
                            setFieldValue(supportsFieldname, event?.target.checked);
                            handleSetTouched(supportsFieldname);
                        }}
                    />
                </div>
            </div>
            <div className="row">
                <div className="col">
                    <SwayTextArea
                        field={{
                            name: positionFieldname,
                            component: "textarea",
                            type: "text",
                            label: `${organizationName} Position Summary`,
                            isRequired: true,
                        }}
                        value={summary}
                        error={error}
                        setFieldValue={handleChange}
                        handleSetTouched={handleSetTouched}
                        helperText={`Why does ${organizationName} ${
                            isSupporting ? "support" : "oppose"
                        } this bill?`}
                    />
                </div>
                <div className="col">
                    <BillSummaryMarkdown summary={summary} />
                </div>
            </div>
        </div>
    );
};

export default BillCreatorOrganization;
