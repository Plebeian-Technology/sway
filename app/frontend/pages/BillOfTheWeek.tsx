/** @format */

import { useEffect } from "react";

import { useCancellable } from "../hooks/useCancellable";
import { useIsUserRegistrationComplete } from "../hooks/users/useIsUserRegistrationComplete";

import { sway } from "sway";
import LocaleSelector from "../components/user/LocaleSelector";
import { notify } from "../sway_utils";
import Bill from "./Bill";

const BillOfTheWeek: React.FC<{bill: sway.IBill}> = ({ bill: billOfTheWeek }) => {
    useEffect(() => {
        const timeout = setTimeout(() => {
            if (!billOfTheWeek) {
                notify({
                    level: "error",
                    title: "Error getting bill of the week.",
                    message: "Please try logging in again.",
                });
                setTimeout(() => {
                    window.location.href = "/";
                }, 2000);
            }
        }, 20000);
        return () => clearTimeout(timeout);
    }, [billOfTheWeek]);

    // if (isLoadingBill) {
    //     return <FullScreenLoading message="Loading Bill of the Week..." />;
    // }

    // Handled in isLoading but Typescript doesn't recognize that
    if (!billOfTheWeek.externalId) return null;

    return (
        <div className="col pb-5">
            <div className="row">
                <div className="col">
                    <LocaleSelector />
                </div>
            </div>
            <div className="row pb-5">
                <div className="col pb-5">
                    <Bill bill={billOfTheWeek} />
                </div>
            </div>
        </div>
    );
};

export default BillOfTheWeek;
