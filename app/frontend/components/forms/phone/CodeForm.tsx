import { PHONE_INPUT_TRANSFORMER } from "app/frontend/sway_utils/phone";
import { PropsWithChildren, useCallback } from "react";
import { Form } from "react-bootstrap";
import { useInertiaForm } from "use-inertia-form";

const CodeForm = ({ children }: PropsWithChildren) => {
    const { data, setData, errors, put, processing } = useInertiaForm<{ code: string }>({ code: "" });

    const onSubmit = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();
            put("/phone_verification/0");
        },
        [put],
    );

    return (
        <Form onSubmit={onSubmit}>
            <Form.Group controlId="code">
                <Form.FloatingLabel label="Code:">
                    <Form.Control
                        maxLength={6}
                        type="text"
                        name="code"
                        autoComplete="one-time-code"
                        isInvalid={!!errors.code}
                        disabled={processing}
                        onChange={(e) => setData("code", e.target.value)}
                    />
                </Form.FloatingLabel>
            </Form.Group>
            {errors.code && <span className="text-white">{errors.code}</span>}
            {children}
        </Form>
    );
};

export default CodeForm;
