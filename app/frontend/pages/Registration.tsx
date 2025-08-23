/** @format */

import { useCallback, useState } from "react";
import { Badge, Button, Form } from "react-bootstrap";
import { FiExternalLink, FiGithub } from "react-icons/fi";
import { sway } from "sway";
import { useLogout } from "../hooks/users/useLogout";

import FormContext from "app/frontend/components/contexts/FormContext";
import toast from "react-hot-toast";
import { useInertiaForm } from "use-inertia-form";
import Dialog404 from "../components/dialogs/Dialog404";
import RegistrationFields from "../components/user/RegistrationFields";
import { notify } from "../sway_utils";

const REGISTRATION_FIELDS: sway.IFormField<sway.IUser>[] = [
    {
        name: "address",
        component: "text",
        type: "text",
        label: "Address (ex. 1 W Elm St)",
        isRequired: true,
        autoComplete: "shipping address",
    },
];

export interface IValidateResponseData {
    street: string;
    street2: string;
    region: string;
    city: string;
    postal_code: string;
}

interface IProps {
    user: sway.IUser;
}

const Registration: React.FC<IProps> = ({ user }) => {
    const logout = useLogout();

    const form = useInertiaForm<sway.IAddress>(user.address);
    const { post } = form;
    const [isLoading, setLoading] = useState<boolean>(false);

    const handleSubmit = useCallback(
        (event: React.FormEvent) => {
            event.preventDefault();

            setLoading(true);
            const toastId = notify({
                level: "info",
                title: "Finding your representatives.",
                message: "Matching your address to your local and congressional legislators may take a minute...",
                duration: 0,
            });

            post("/sway_registration", {
                onFinish: () => {
                    toast.dismiss(toastId);
                    setLoading(false);
                },
                async: false,
            });
        },
        [post],
    );

    const openUrl = useCallback((url: string) => {
        window.open(url, "_blank");
    }, []);

    if (!user?.id) return <Dialog404 />;

    return (
        <div className="row">
            <div className="col">
                <div>
                    <p>
                        Sway requires additional information about you in order to match you with your representatives.
                    </p>
                </div>
                <FormContext.Provider value={form}>
                    <Form onSubmit={handleSubmit}>
                        <RegistrationFields
                            user={user}
                            isLoading={isLoading}
                            setLoading={setLoading}
                            field={REGISTRATION_FIELDS.first()}
                        />
                        <div className="d-flex flex-row align-items-center justify-content-end">
                            <Button variant="light" onClick={logout} className="me-3">
                                Cancel
                            </Button>
                            <Button disabled={isLoading} type="submit" className="my-2">
                                Submit
                            </Button>
                        </div>
                    </Form>
                </FormContext.Provider>
            </div>
            <hr />
            <div>
                <div className="my-1">
                    If you are registered to vote, please complete each of the following fields to match - as closely as
                    possible - what is on your voter registration.
                </div>
                <hr />
                <div className="my-1">
                    If you are not registered to vote, it is not required by Sway, but is{" "}
                    <span className="bold">strongly</span> recommended. You can register to vote&nbsp;
                    <Badge
                        pill
                        className="pointer"
                        bg="info"
                        onClick={() => openUrl("https://www.vote.org/register-to-vote/")}
                    >
                        <FiExternalLink />
                        &nbsp;here
                    </Badge>
                </div>
                <div className="mt-2 mb-1">
                    You can find your current voter registration&nbsp;
                    <Badge
                        pill
                        className="pointer"
                        bg="info"
                        onClick={() => openUrl("https://www.vote.org/am-i-registered-to-vote/")}
                    >
                        <FiExternalLink />
                        &nbsp;here
                    </Badge>
                </div>
            </div>
            <hr />
            <div className="pb-5">
                <p className="my-1">
                    If you want to see more about how Sway works under-the-hood, code for Sway is available on&nbsp;
                    {
                        <Badge
                            pill
                            className="pointer"
                            bg="info"
                            onClick={() => openUrl("https://github.com/Plebeian-Technology/sway")}
                        >
                            <FiGithub />
                            &nbsp;Github
                        </Badge>
                    }
                </p>
            </div>
        </div>
    );
};

export default Registration;
