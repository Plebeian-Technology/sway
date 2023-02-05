/** @format */
import { Support } from "@sway/constants";
import { get } from "lodash";

import { Form } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    legislator: sway.ILegislator;
    values: sway.IPlainObject;
    touched: sway.IPlainObject;
    setFieldValue: (fieldname: string, fieldvalue: string) => void;
    setTouched: (values: Record<string, unknown>) => void;
    style?: React.CSSProperties;
}

const LegislatorPositionInput: React.FC<IProps> = ({
    legislator,
    values,
    touched,
    setFieldValue,
    setTouched,
}) => {
    const fieldname = legislator.externalId;
    const position = get(values?.legislators, fieldname);

    return (
        <div>
            <p>{legislator.full_name}</p>
            <span>{Support.For}</span>
            <Form.Check
                onChange={() => {
                    setTouched({
                        ...touched,
                        [`legislators.${legislator.externalId}`]: true,
                    });
                    setFieldValue(`legislators.${legislator.externalId}`, Support.For);
                }}
                checked={position === Support.For}
                name={`legislators.${fieldname}`}
            />
            <span>{Support.Against}</span>
            <Form.Check
                onChange={() => {
                    setTouched({
                        ...touched,
                        [`legislators.${legislator.externalId}`]: true,
                    });
                    setFieldValue(`legislators.${legislator.externalId}`, Support.Against);
                }}
                checked={position === Support.Against}
                name={`legislators.${fieldname}`}
            />
            <span>{Support.Abstain}</span>
            <Form.Check
                onChange={() => {
                    setTouched({
                        ...touched,
                        [`legislators.${legislator.externalId}`]: true,
                    });
                    setFieldValue(`legislators.${legislator.externalId}`, Support.Abstain);
                }}
                checked={position === Support.Abstain}
                name={`legislators.${fieldname}`}
            />
        </div>
    );
};

export default LegislatorPositionInput;
