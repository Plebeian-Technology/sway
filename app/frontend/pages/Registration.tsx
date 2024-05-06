/** @format */

import { Form, Formik } from "formik";
import { useCallback, useState } from "react";
import { Badge, Button } from "react-bootstrap";
import { FiExternalLink, FiGithub } from "react-icons/fi";
import { sway } from "sway";
import { useLogout } from "../hooks/users/useLogout";

import { useAxiosPost } from "app/frontend/hooks/useAxios";
import { setSwayLocale, setSwayLocales } from "app/frontend/redux/actions/localeActions";
import { setUser } from "app/frontend/redux/actions/userActions";
import toast from "react-hot-toast";
import { useDispatch } from "react-redux";
import Dialog404 from "../components/dialogs/Dialog404";
import RegistrationFields from "../components/user/RegistrationFields";
import { handleError, notify } from "../sway_utils";

const REGISTRATION_FIELDS: sway.IFormField[] = [
    // {
    //     name: "name",
    //     component: "text",
    //     type: "text",
    //     label: "Name (ex. Abraham Lincoln)",
    //     isRequired: true,
    //     autoComplete: "name",
    // },
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
    postalCode: string;
    postalCodeExtension: string;
}

interface IProps {
    user: sway.IUser;
}

const Registration: React.FC<IProps> = ({ user }) => {
    const dispatch = useDispatch();
    const logout = useLogout();

    const { post } = useAxiosPost("/sway_registration");
    const [isLoading, setLoading] = useState<boolean>(false);

    const handleSubmit = useCallback(
        async (address: sway.IAddress) => {
            setLoading(true);
            const toastId = notify({
                level: "info",
                title: "Finding your representatives.",
                message: "Matching your address to your local and congressional legislators may take a minute...",
                duration: 0,
            });

            post({ ...address })
                .then((result) => {
                    if (result && "user" in result) {
                        dispatch(setUser(result.user));
                    }
                    if (result && "sway_locale" in result) {
                        dispatch(setSwayLocale(result.sway_locale));
                        dispatch(setSwayLocales([result.sway_locale]));
                    }
                    if (result && "swayLocale" in result) {
                        dispatch(setSwayLocale(result.swayLocale));
                        dispatch(setSwayLocales([result.swayLocale]));
                    }
                })
                .catch(handleError)
                .finally(() => {
                    toast.dismiss(toastId);
                    setLoading(false);
                });
        },
        [dispatch, post],
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
                <Formik
                    initialValues={{} as sway.IAddress}
                    onSubmit={handleSubmit}
                    // validationSchema={VALIDATION_SCHEMA}
                    enableReinitialize={true}
                >
                    <Form>
                        <RegistrationFields
                            user={user}
                            isLoading={isLoading}
                            setLoading={setLoading}
                            fields={REGISTRATION_FIELDS}
                        />
                        <div className="row align-items-center">
                            <div className="col text-start">
                                <Button variant="outline-light" onClick={logout}>
                                    Cancel
                                </Button>
                            </div>
                            <div className="col text-end">
                                <Button disabled={isLoading} type="submit" className="my-2">
                                    Submit
                                </Button>
                            </div>
                        </div>
                    </Form>
                </Formik>
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
                {/* <p>
                    We take privacy very seriously. If you have any questions about what happens to
                    your data please see our privacy policy, or contact our internal privacy auditor
                    at{" "}
                    <Badge
                        pill
                        className="pointer"
                        bg="info"
                        onClick={() => handleCopy("privacy@sway.vote")}
                    >
                        <FiCopy />
                        &nbsp;privacy@sway.vote
                    </Badge>
                </p> */}
                {/* <hr /> */}
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
