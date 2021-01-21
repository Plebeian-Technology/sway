/** @format */

import Divider from "@material-ui/core/Divider";
import List from "@material-ui/core/List";
import { CONGRESS_LOCALE_NAME, LOCALES } from "@sway/constants";
import React, { useCallback, useEffect, useState } from "react";
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
    const [billLocale, setBillLocale] = useState(locale);
    const [categories, setCategories] = useState<string[]>([]);
    const [isLoading, setIsLoading] = useState<boolean>(false);
    const { bills }: { bills: sway.IBillWithOrgs[] } = useSelector(
        (state: sway.IAppState) => state?.bills,
    );

    const uid = user?.uid;
    const registered = user?.isRegistrationComplete;

    const dispatchBills = useCallback(
        (_bills: sway.IBillWithOrgs[]) => {
            dispatch(setBills(_bills));
        },
        [dispatch],
    );

    const billsCount = bills ? bills.length : 0;

    useEffect(() => {
        const _addOrganizations = async (_bill: sway.IBill) => {
            if (!billLocale) return;

            const organizations = await legisFire(billLocale)
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
                if (!uid || !registered || !billLocale)
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
            if (!billLocale) return;

            const _bills = await legisFire(billLocale).bills().list(categories);
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

        loadBills().catch(console.error);
    }, [uid, registered, billLocale, billsCount, categories, dispatchBills]);

    if (isLoading || (isEmptyObject(bills) && isEmptyObject(categories))) {
        return (
            <FullWindowLoading message={"Loading Past Bills of the Week..."} />
        );
    }

    const handleSetCategories = (_categories: string[]) => {
        setIsLoading(true);
        setCategories(_categories);
    };

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
                                locale={billLocale}
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
                        locale={billLocale}
                        bill={item.bill}
                        organizations={item.organizations}
                        index={index}
                    />
                );
            })
            .filter(Boolean);
    };

    const getLocales = () => {
        if (!user || !user?.locale?.name) {
            return LOCALES;
        }
        return LOCALES.filter(
            (l) =>
                l.name === user?.locale?.name ||
                l.name === CONGRESS_LOCALE_NAME,
        );
    };

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={billLocale}
                    locales={getLocales()}
                    setLocale={setBillLocale}
                    containerStyle={{ width: "90%" }}
                />
            </div>
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
