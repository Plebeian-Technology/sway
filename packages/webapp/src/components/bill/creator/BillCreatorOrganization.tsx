import { FormControlLabel, Switch } from "@mui/material";
import { useEffect, useState } from "react";
import { withEmojis } from "../../../utils/emoji";
import SwayTextArea from "../../forms/SwayTextArea";
import BillSummaryMarkdown from "../BillSummaryMarkdown";

interface IProps {
    organizationName: string;
    isSupporting: boolean;
    setFieldValue: (
        fieldname: string,
        fieldvalue: string[] | string | boolean | null,
    ) => void;
    handleSetTouched: (fieldname: string) => void;
    error: string;
}

const BillCreatorOrganization: React.FC<IProps> = ({
    organizationName,
    setFieldValue,
    handleSetTouched,
    isSupporting,
    error,
}) => {
    const fieldname = `positions.${organizationName}`;
    const positionFieldname = `${fieldname}.position`;
    const supportsFieldname = `${fieldname}.support`;

    const [summary, setSummary] = useState<string>("");
    useEffect(() => {
        const sendValue = async () => {
            setFieldValue(fieldname, summary);
            handleSetTouched(fieldname);
        };
        sendValue().catch(console.error);
    }, [summary]);

    const handleChange = async (_fieldname: string, fieldvalue: string) => {
        setSummary(withEmojis(fieldvalue));
    };

    return (
        <div className="col py-2">
            <div className="row">
                <div className="col">
                    <FormControlLabel
                        label={isSupporting ? "Supports" : "Opposes"}
                        className="mb-1"
                        control={
                            <Switch
                                name={supportsFieldname}
                                checked={isSupporting}
                                onChange={(
                                    event: React.ChangeEvent<HTMLInputElement>,
                                ) => {
                                    setFieldValue(
                                        supportsFieldname,
                                        event?.target.checked,
                                    );
                                    handleSetTouched(supportsFieldname);
                                }}
                            />
                        }
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
                        rows={5}
                        value={summary}
                        error={error}
                        setFieldValue={handleChange}
                        handleSetTouched={handleSetTouched}
                        helperText={`Why does ${organizationName} ${
                            isSupporting ? "support" : "oppose"
                        } this bill?.`}
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
