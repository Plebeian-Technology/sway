/** @format */

import { ISubmitValues } from "app/frontend/components/admin/types";
import { useFormContext } from "app/frontend/components/contexts/hooks/useFormContext";
import { Form } from "react-bootstrap";
import { sway } from "sway";

interface IProps<T> {
    field: sway.IFormField<T>;
    value: boolean;
    error: string;
}

const SwayFormCheckbox = <T,>({ field, value }: IProps<T>) => {
    const { setData } = useFormContext<ISubmitValues>();
    return (
        <>
            <Form.Label className="me-2">{`${field.label} - ${value}`}</Form.Label>
            &nbsp;
            <Form.Check
                type={"checkbox"}
                className="p-2"
                name={field.name}
                onChange={(e) => setData(field.name, e.target.checked)}
            />
        </>
    );
};

export default SwayFormCheckbox;
