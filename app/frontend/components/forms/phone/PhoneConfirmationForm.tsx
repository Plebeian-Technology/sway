import { usePage } from "@inertiajs/react";
import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import CodeForm from "app/frontend/components/forms/phone/CodeForm";
import PhoneForm from "app/frontend/components/forms/phone/PhoneForm";
import { noop } from "lodash";
import { Fade, Button } from "react-bootstrap";

const PhoneConfirmationForm = () => {
    const { is_confirming_phone } = usePage().props.params as { is_confirming_phone: "0" | "1" };
    const isConfirmingPhone = is_confirming_phone === "1";

    return (
        <div className="col">
            <div className="row my-2">
                <div className="col-lg-4 col-1">&nbsp;</div>
                <div className="col-lg-4 col-10">
                    <PhoneForm>{isConfirmingPhone ? <></> : <Buttons />}</PhoneForm>
                </div>
                <div className="col-lg-4 col-1">&nbsp;</div>

                <div className="col-lg-4 col-1">&nbsp;</div>
                <div className="col-lg-4 col-10">
                    {isConfirmingPhone && (
                        <CodeForm>
                            <Buttons />
                        </CodeForm>
                    )}
                </div>
                <div className="col-lg-4 col-1">&nbsp;</div>
            </div>

            <div className="row">
                <div className="col text-center">
                    <CenteredLoading className="white" isHidden={!false} />
                </div>
            </div>
        </div>
    );
};

const Buttons = () => {
    const { is_confirming_phone } = usePage().props.params as { is_confirming_phone: "0" | "1" };
    const isConfirmingPhone = is_confirming_phone === "1";

    return (
        <div className="row my-2">
            <div className="col-lg-4 col-1">&nbsp;</div>
            <div className="col">
                <Fade in={isConfirmingPhone}>
                    <Button className="w-100" variant="outline-light" disabled={false} onClick={noop}>
                        Cancel
                    </Button>
                </Fade>
            </div>
            <div className="col">
                <Button className="w-100" variant="primary" type="submit" disabled={false}>
                    Submit
                </Button>
            </div>
            <div className="col-lg-4 col-1">&nbsp;</div>
        </div>
    );
};

export default PhoneConfirmationForm;
