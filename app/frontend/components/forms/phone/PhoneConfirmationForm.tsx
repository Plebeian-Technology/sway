import { usePage } from "@inertiajs/react";
import CodeForm from "app/frontend/components/forms/phone/CodeForm";
import PhoneForm from "app/frontend/components/forms/phone/PhoneForm";

const PhoneConfirmationForm = () => {
    const { is_verifying } = usePage().props.params as { is_verifying: "0" | "1" };

    return (
        <div className="col">
            <PhoneForm disabled={is_verifying === "1"} />
            {is_verifying === "1" && <CodeForm />}
        </div>
    );
};

export default PhoneConfirmationForm;
