import { Form } from "react-bootstrap";

interface IProps {
    name: string;
    id: string;
    label: string | React.JSX.Element;
    checked: boolean;
    disabled?: boolean;
    onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
}

const SwayCheckbox: React.FC<IProps> = ({ name, id, label, checked, disabled, onChange }) => {
    return (
        <Form.Check
            label={label}
            name={name}
            id={id}
            disabled={!!disabled || false}
            checked={checked}
            onChange={onChange}
        />
    );
};

export default SwayCheckbox;
