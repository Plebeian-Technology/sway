import { lazy, Suspense } from "react";
import { Route } from "react-router-dom";
import { useAdmin } from "../../hooks/useUsers";
import BillOfTheWeek from "../bill/BillOfTheWeek";
import BillRoute from "../bill/BillRoute";
import BillsList from "../bill/BillsList";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import LegislatorRoute from "../legislator/LegislatorRoute";
import Legislators from "../legislator/Legislators";
import UserSettings from "./settings/UserSettings";
import UserSwayInfluence from "./UserSwayInfluence";
const BillOfTheWeekCreator = lazy(() => import("../admin/BillOfTheWeekCreator"));

const AuthedUser: React.FC = () => {
    const isAdmin = useAdmin();

    return (
        <>
            <Route path={"legislators"} element={<Legislators />}>
                <Route path=":localeName">
                    <Route path={":externalLegislatorId"} element={<LegislatorRoute />} />
                </Route>
            </Route>

            <Route path={"bill-of-the-week"} element={<BillOfTheWeek />} />
            <Route path={"bills"} element={<BillsList />}>
                <Route path={"bill"}>
                    <Route path={":localeName"}>
                        <Route path={":billFirestoreId"} element={<BillRoute />} />
                    </Route>
                </Route>
            </Route>

            <Route path={"influence"} element={<UserSwayInfluence />} />

            <Route path={"settings"} element={<UserSettings />} />

            {isAdmin && (
                <Suspense fallback={<FullScreenLoading />}>
                    <Route path="admin">
                        <Route path="bills">
                            <Route path="creator" element={<BillOfTheWeekCreator />} />
                        </Route>
                    </Route>
                </Suspense>
            )}
        </>
    );
};

export default AuthedUser;
