/** @format */

import Divider from "@material-ui/core/Divider";
import List from "@material-ui/core/List";
import React from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { setBills } from "../../redux/actions/billActions";
import { isEmptyObject, legisFire, removeTimestamps } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import SwayFab from "../fabs/SwayFab";
import LocaleSelector from "../user/LocaleSelector";
import { ILocaleUserProps } from "../user/UserRouter";
import BillsListHeader from "./BillsListHeader";
import BillsListItem from "./BillsListItem";

const BillsList: React.FC<ILocaleUserProps> = ({ user, locale }) => {
    const dispatch = useDispatch();
    const [categories, setCategories] = React.useState<string[]>([]);
    const [isLoading, setIsLoading] = React.useState<boolean>(false);
    const { bills }: { bills: sway.IBillWithOrgs[] } = useSelector(
        (state: sway.IAppState) => state?.bills,
    );

    const uid = user?.uid;
    const registered = user?.isRegistrationComplete;

    const dispatchBills = React.useCallback(
        (_bills: sway.IBillWithOrgs[]) => {
            dispatch(setBills(_bills));
        },
        [dispatch],
    );

    const billsCount = bills ? bills.length : 0;

    React.useEffect(() => {
        const _addOrganizations = async (_bill: sway.IBill) => {
            if (!locale) return;

            const organizations = await legisFire(locale)
                .organizations()
                .listPositions(_bill.firestoreId);
            return organizations;
        };

        const addOrganizations = (_bills: sway.IBill[]) => {
            return _bills.map(async (_bill: sway.IBill) => {
                const __bill = removeTimestamps(_bill);

                // NOTE: Redux can't serialize firebase timestamps, need to remove
                const _score: sway.IBillScore = removeTimestamps(__bill.score);
                const bill: sway.IBill = {
                    ...__bill,
                    score: _score,
                };

                const organizations = await _addOrganizations(bill);
                if (!uid || !registered || !locale)
                    return { bill, organizations };

                return { bill, organizations };
            }) as Promise<sway.IBillWithOrgs>[];
        };

        const billsWithOrgs = async (_bills: sway.IBill[]) => {
            return Promise.all(addOrganizations(_bills))
                .then((bvorgs: sway.IBillWithOrgs[]) => {
                    dispatchBills(bvorgs);
                })
                .catch(console.error);
        };

        const loadBills = async () => {
            if (!locale) return;

            const _bills = await legisFire(locale).bills().list(categories);
            if (!_bills) {
                console.log("NO BILLS");

                return;
            }

            billsWithOrgs(_bills)
                .catch(console.error)
                .finally(() => {
                    setIsLoading(false);
                });
        };

        locale && loadBills();
    }, [uid, registered, locale, billsCount, categories, dispatchBills]);

    if (isLoading || (isEmptyObject(bills) && isEmptyObject(categories))) {
        return (
            <FullWindowLoading message={"Loading Past Bills of the Week..."} />
        );
    }

    const handleSetCategories = (_categories: string[]) => {
        setIsLoading(true);
        setCategories(_categories);
    };

    const localeName = user?.locale?.name ? user.locale.name : locale?.name;

    const render = () => {
        if (isEmptyObject(bills)) {
            const message = `No bills in categories - ${categories.join(", ")}`;
            return <p className="no-legislators-message">{message}</p>;
        }
        return bills
            .map((item: sway.IBillWithOrgs, index: number) => {
                if (
                    !isEmptyObject(categories) &&
                    item.bill.category &&
                    !categories.includes(item.bill.category)
                ) {
                    return null;
                }

                if (index !== bills.length - 1) {
                    return (
                        <React.Fragment key={index}>
                            <BillsListItem
                                user={user}
                                localeName={localeName}
                                bill={item.bill}
                                organizations={item.organizations}
                                index={index}
                            />
                            <Divider variant="inset" component="li" />
                        </React.Fragment>
                    );
                }
                return (
                    <BillsListItem
                        user={user}
                        key={index}
                        localeName={localeName}
                        bill={item.bill}
                        organizations={item.organizations}
                        index={index}
                    />
                );
            })
            .filter(Boolean);
    };

    const renderLocaleSelector = () => {
        return (
            <div className={"bill-of-the-week-locale-selector-container"}>
                <LocaleSelector containerStyle={{ width: "90%" }} />
            </div>
        );
    };

    return (
        <>
            {!user?.uid && renderLocaleSelector()}
            <BillsListHeader
                categories={categories}
                setCategories={handleSetCategories}
            />
            <List>{render()}</List>
            <SwayFab user={user} />
        </>
    );
};
export default BillsList;
