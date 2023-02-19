/** @format */

import { NOTIFY_COMPLETED_REGISTRATION, ROUTES } from "@sway/constants";
import { isEmptyObject, logDev } from "@sway/utils";
import { Fragment, useCallback, useEffect, useMemo } from "react";
import { Button } from "react-bootstrap";
import { useLocation, useNavigate } from "react-router";
import { sway } from "sway";

import { useRepresentatives } from "../../hooks/useRepresentatives";
import { useEmailVerification } from "../../hooks/useEmailVerification";
import { handleError, localGet, localSet, notify, SWAY_STORAGE, withTadas } from "../../utils";
import LocaleAvatar from "../locales/LocaleAvatar";
import SwaySpinner from "../SwaySpinner";
import LocaleSelector from "../user/LocaleSelector";
import LegislatorCard from "./LegislatorCard";
import { useFirebaseUser } from "../../hooks/users/useFirebaseUser";
import { useIsUserEmailVerified } from "../../hooks/users/useIsUserEmailVerified";

const Legislators: React.FC = () => {
    const navigate = useNavigate();
    const [user] = useFirebaseUser();
    const { search } = useLocation();

    const sendEmailVerification = useEmailVerification();
    const isEmailVerified = useIsUserEmailVerified();
    const [representatives, getRepresentatives, isLoading] = useRepresentatives();

    const handleSendEmailVerification = useCallback(() => {
        sendEmailVerification(user).catch(handleError);
    }, [sendEmailVerification, user]);

    useEffect(() => {
        const searchParams = new URLSearchParams(search);
        const queryStringCompletedRegistration =
            searchParams && searchParams.get(NOTIFY_COMPLETED_REGISTRATION);
        if (queryStringCompletedRegistration === "1") {
            if (localGet(NOTIFY_COMPLETED_REGISTRATION)) {
                searchParams.delete(NOTIFY_COMPLETED_REGISTRATION);
            } else {
                localSet(NOTIFY_COMPLETED_REGISTRATION, "1");
                notify({
                    level: "success",
                    title: withTadas("Welcome to Sway"),
                    message: "Click/tap here to start voting and earning Sway!",
                    tada: true,
                    duration: 200000,
                    onClick: () => navigate(ROUTES.billOfTheWeek),
                });
            }
        }
    }, [navigate, search]);

    useEffect(() => {
        localSet(SWAY_STORAGE.Local.User.Registered, "true");
        logDev("Legislators.useEffect - getRepresentatives");
        getRepresentatives(true);
    }, [getRepresentatives]);

    const render = useMemo(() => {
        if (isEmptyObject(representatives)) {
            return <p>No Representatives</p>;
        }

        return representatives.map((legislator: sway.ILegislator, index: number) => (
            <Fragment key={legislator.externalId}>
                <div
                    className={`row p-3 m-3 border rounded border-primary ${
                        index > 0 ? "my-3" : ""
                    }`}
                >
                    <LegislatorCard legislator={legislator} />
                </div>
                {index === representatives.length - 1 ? null : (
                    <div className="col-12 text-center">
                        <LocaleAvatar />
                    </div>
                )}
            </Fragment>
        ));
    }, [representatives]);

    return (
        <div className="row pb-5">
            <div className="col pb-5">
                {isEmailVerified === false && (
                    <div className="row my-3 w-100">
                        <div className="col text-center">
                            <Button variant="info" onClick={handleSendEmailVerification}>
                                Verify email to start voting!
                            </Button>
                        </div>
                    </div>
                )}
                <div className="row">
                    <div className="col">
                        <LocaleSelector />
                    </div>
                </div>
                <div className="row">
                    <div className="col">
                        {isLoading ? (
                            <SwaySpinner
                                message="Loading your representatives..."
                                className="mt-2"
                            />
                        ) : (
                            render
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
};

export default Legislators;
