/** @format */

import { useFormikContext } from "formik";
import { Form } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    field: sway.IFormField;
    value: boolean;
    error: string;
}

const SwayFormCheckbox: React.FC<IProps> = ({ field, value }) => {
    const { handleChange } = useFormikContext();
    return (
        <>
            <Form.Label className="me-2">{`${field.label} - ${value}`}</Form.Label>
            &nbsp;
            <Form.Check type={"checkbox"} className="p-2" name={field.name} onChange={handleChange} />
        </>
    );
};

export default SwayFormCheckbox;
