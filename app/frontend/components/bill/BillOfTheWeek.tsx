/** @format */

import { logDev } from "app/frontend/sway_utils";
import { useEffect } from "react";
import { LOAD_ERROR_MESSAGE } from "../../sway_constants";
import { useBillOfTheWeek } from "../../hooks/useBillOfTheWeek";
import { useCancellable } from "../../hooks/useCancellable";
import { useIsUserRegistrationComplete } from "../../hooks/users/useIsUserRegistrationComplete";
import { anonymousSignIn } from "../../users/signinAnonymously";
import { handleError, notify } from "../../sway_utils";
import LocaleSelector from "../user/LocaleSelector";
import Bill from "./Bill";

const BillOfTheWeek: React.FC = () => {
    const makeCancellable = useCancellable();
    const isRegistrationComplete = useIsUserRegistrationComplete();
    const [billOfTheWeek, getBillOfTheWeek] = useBillOfTheWeek();

    useEffect(() => {
        const load = async () => {
            if (isRegistrationComplete === undefined) {
                logDev(
                    "Bill.useEffect - getBillOfTheWeek() isRegistrationComplete === undefined. No-op",
                );
            } else if (!isRegistrationComplete) {
                logDev("Bill.useEffect - getBillOfTheWeek() WITH ANONYMOUS USER");
                anonymousSignIn()
                    .then(getBillOfTheWeek)
                    .catch((error: Error) => {
                        handleError(error, LOAD_ERROR_MESSAGE);
                    });
            } else {
                logDev("Bill.useEffect - getBillOfTheWeek() WITH REGISTERED USER");
                getBillOfTheWeek();
            }
        };
        makeCancellable(load()).catch(handleError);
    }, [getBillOfTheWeek, isRegistrationComplete, makeCancellable]);

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
    if (!billOfTheWeek?.bill.firestoreId) return null;

    return (
        <div className="col pb-5">
            <div className="row">
                <div className="col">
                    <LocaleSelector />
                </div>
            </div>
            <div className="row pb-5">
                <div className="col pb-5">
                    <Bill billFirestoreId={billOfTheWeek.bill.firestoreId} />
                </div>
            </div>
        </div>
    );
};

export default BillOfTheWeek;
