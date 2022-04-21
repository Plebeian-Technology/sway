/** @format */
import { ROUTES } from "@sway/constants";
import { useEffect, useState } from "react";
import { Button } from "react-bootstrap";
import { FaRegistered } from "react-icons/fa";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import SwaySvg from "../SwaySvg";

interface IProps {
    user: sway.IUser | undefined;
}

const RegistrationIntroduction: React.FC<IProps> = () => {
    const navigate = useNavigate();
    const [isLoadingComponent, setLoadingComponent] = useState<boolean>(true);

    useEffect(() => {
        setLoadingComponent(false);
    }, [setLoadingComponent]);

    const handleGoToRegistration = () => {
        navigate(ROUTES.registration);
    };

    return (
        <div className={"registration-container"}>
            <div id="subcontainer">
                <div>
                    <p>
                        Sway requires additional information about you in order to match you with
                        your representatives.
                    </p>
                    <p>
                        We take privacy very seriously. If you have any questions about what happens
                        to your data please see our privacy policy, or contact our internal privacy
                        auditor at{" "}
                        <a className="link" href="mailto:privacy@sway.vote">
                            privacy@sway.vote
                        </a>
                        .
                    </p>
                    {/* <p
                        
                        
                    >
                        We also offer virtual walkthroughs of Sway, showcasing
                        where and how your data is stored. To schedule a
                        walkthrough send an email to{" "}
                        <a
                            
                            href="mailto:privacy@sway.vote"
                        >
                            privacy@sway.vote
                        </a>
                        .
                    </p> */}
                    {/* <p
                                    
                                    component="p"
                                    variant="body1"
                                    color="textPrimary"
                                >
                                    If you want to see more about how Sway
                                    works under-the-hood, code for Sway is
                                    open-source and publicly viewable and
                                    editable on Github at{" "}
                                    <a  href="https://www.github.com/plebeian-technologies/sway">
                                        https://www.github.com/plebeian-technologies/sway
                                    </a>
                                    .
                                </p> */}
                </div>
                <hr />
                <div>
                    <p style={{ marginTop: 1, marginBottom: 1 }}>
                        If you are registered to vote, please complete each of the following fields
                        to match, as closely as possible, what is on your voter registration.
                    </p>
                    <p style={{ marginTop: 1, marginBottom: 1 }}>
                        If you are not registered to vote, it is not required but is{" "}
                        <span className="bold">strongly</span> recommended. You can register to vote
                        <a target={"_blank"} href="https://www.vote.org/register-to-vote/">
                            {" here."}
                        </a>
                    </p>
                    <p style={{ marginTop: 1, marginBottom: 1 }}>
                        You can find your current voter registration
                        <a target={"_blank"} href="https://www.vote.org/am-i-registered-to-vote/">
                            {" here."}
                        </a>
                    </p>
                </div>
                <hr />
                <div>
                    <p style={{ marginTop: 1, marginBottom: 1 }}>
                        If you want to see more about how Sway works under-the-hood, code for Sway
                        is available on{" "}
                        {
                            <Button
                                disabled={isLoadingComponent}
                                style={{ padding: "0.5em 1em", margin: 0 }}
                                variant="contained"
                                color="primary"
                                onClick={() =>
                                    window.open("https://github.com/Plebeian-Technology/sway")
                                }
                            >
                                <SwaySvg
                                    src={"/icons/github.svg"}
                                    containerStyle={{ margin: "0px" }}
                                />
                                &nbsp;Github
                            </Button>
                        }
                    </p>
                </div>
                <div>
                    <Button disabled={isLoadingComponent} onClick={handleGoToRegistration}>
                        <FaRegistered />
                        &nbsp;Complete Sway Registration
                    </Button>
                </div>
            </div>
        </div>
    );
};

export default RegistrationIntroduction;
