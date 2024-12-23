import { PHONE_INPUT_TRANSFORMER } from "app/frontend/sway_utils/phone";
import { useCallback } from "react";
import { Form } from "react-bootstrap";
import { useInertiaForm } from "use-inertia-form";

interface IProps {
    disabled?: boolean;
}

const PhoneForm: React.FC<IProps> = ({ disabled }) => {
    const { data, setData, errors, post, processing } = useInertiaForm<{ phone: string }>({ phone: "" });

    const onSubmit = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            post("/users/webauthn/registration");
        },
        [post],
    );

    return (
        <Form onSubmit={onSubmit}>
            <Form.Group controlId="phone">
                <Form.FloatingLabel label="Please enter your phone number...">
                    <Form.Control
                        maxLength={16}
                        type="tel"
                        name="phone"
                        autoComplete="tel webauthn"
                        isInvalid={!!errors.phone}
                        value={PHONE_INPUT_TRANSFORMER.input(data.phone)}
                        disabled={disabled || processing}
                        onChange={(e) => setData("phone", e.target.value)}
                    />
                </Form.FloatingLabel>
            </Form.Group>
        </Form>
    );
};

export default PhoneForm;
