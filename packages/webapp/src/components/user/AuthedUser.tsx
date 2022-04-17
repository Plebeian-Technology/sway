import { lazy } from "react";
import { Route } from "react-router-dom";
import { sway } from "sway";
import BillOfTheWeek from "../bill/BillOfTheWeek";
import BillRoute from "../bill/BillRoute";
import BillsList from "../bill/BillsList";
import LegislatorRoute from "../legislator/LegislatorRoute";
import Legislators from "../legislator/Legislators";
import UserSettings from "./settings/UserSettings";
import UserSwayInfluence from "./UserSwayInfluence";
const BillOfTheWeekCreator = lazy(() => import("../admin/BillOfTheWeekCreator"));

interface IProps {
    userWithSettingsAdmin: sway.IUserWithSettingsAdmin | undefined;
}

const AuthedUser: React.FC<IProps> = ({ userWithSettingsAdmin }) => {
    const isAdmin = Boolean(userWithSettingsAdmin?.isAdmin);
    const user = userWithSettingsAdmin?.user;

    return (
        <>
            <Route path={"legislators"} element={<Legislators user={user} />}>
                <Route path=":localeName">
                    <Route
                        path={":externalLegislatorId"}
                        element={<LegislatorRoute user={user} />}
                    />
                </Route>
            </Route>

            <Route path={"bill-of-the-week"} element={<BillOfTheWeek user={user} />} />
            <Route path={"bills"} element={<BillsList user={user} />}>
                <Route path={"bill"}>
                    <Route path={":localeName"}>
                        <Route path={":billFirestoreId"} element={<BillRoute user={user} />} />
                    </Route>
                </Route>
            </Route>

            <Route path={"influence"} element={<UserSwayInfluence user={user} />} />

            <Route
                path={"settings"}
                element={<UserSettings userWithSettingsAdmin={userWithSettingsAdmin} />}
            />
            {isAdmin && (
                // <Suspense fallback={<FullScreenLoading />}>
                <Route path="admin">
                    <Route path="bills">
                        <Route path="creator" element={<BillOfTheWeekCreator />} />
                    </Route>
                </Route>
                // </Suspense>
            )}
        </>
    );
};

export default AuthedUser;
