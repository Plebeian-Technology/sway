import { PHONE_INPUT_TRANSFORMER } from "app/frontend/sway_utils/phone";
import { useCallback } from "react";
import { Form } from "react-bootstrap";
import { useInertiaForm } from "use-inertia-form";

const CodeForm = () => {
    const { data, setData, errors, post, processing } = useInertiaForm<{ code: string }>({ code: "" });

    const onSubmit = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            post("/phone_verification/0");
        },
        [post],
    );

    return (
        <Form onSubmit={onSubmit}>
            <Form.Group controlId="code">
                <Form.FloatingLabel label="Please enter your code number...">
                    <Form.Control
                        maxLength={16}
                        type="tel"
                        name="code"
                        autoComplete="tel webauthn"
                        isInvalid={!!errors.code}
                        value={PHONE_INPUT_TRANSFORMER.input(data.code)}
                        disabled={processing}
                        onChange={(e) => setData("phone", e.target.value)}
                    />
                </Form.FloatingLabel>
            </Form.Group>
        </Form>
    );
};

export default CodeForm;
