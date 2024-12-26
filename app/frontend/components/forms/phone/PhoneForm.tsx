import { usePage } from "@inertiajs/react";
import { PHONE_INPUT_TRANSFORMER } from "app/frontend/sway_utils/phone";
import { PropsWithChildren, useCallback } from "react";
import { Form } from "react-bootstrap";
import { useInertiaForm } from "use-inertia-form";

const PhoneForm = ({ children }: PropsWithChildren) => {
    const { is_confirming_phone } = usePage().props.params as { is_confirming_phone: "0" | "1" };

    const { data, setData, errors, post, processing } = useInertiaForm<{ phone: string }>({ phone: "" });

    const onSubmit = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            post("/users/webauthn/sessions");
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
                        disabled={is_confirming_phone === "1" || processing}
                        onChange={(e) => setData("phone", e.target.value)}
                    />
                </Form.FloatingLabel>
            </Form.Group>
            {children}
        </Form>
    );
};

export default PhoneForm;
