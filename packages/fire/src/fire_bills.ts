/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import FireBillScores from "./fire_bill_scores";
import { isEmptyObject } from "./utils";

class FireBills extends AbstractFireSway {
    private collection = () => {
        return this.firestore
            .collection(Collections.BillsOfTheWeek)
            .doc(this?.locale?.name)
            .collection(Collections.BillsOfTheWeek);
    };

    public listen = (
        callback: (
            snapshot: fire.TypedQuerySnapshot<sway.IBill>
        ) => Promise<void>,
        errorCallback?: (params?: any) => void
    ) => {
        if (errorCallback) {
            return this.collection().onSnapshot({
                next: callback,
                error: errorCallback,
            });
        }
        return this.collection().onSnapshot({ next: callback });
    };

    private addBillScore = async (
        bill: sway.IBill
    ): Promise<sway.IBill> => {
        const scorer = new FireBillScores(
            this.firestore,
            this?.locale,
            this.firestoreConstructor
        );
        const score = await scorer.get(bill.firestoreId);
        if (!score) return bill;

        bill.score = score;
        return { ...bill };
    };
    private addFirestoreIdMethodToBill = (
        bill: sway.IBill
    ): sway.IBill => {
        bill.firestoreId = ((_bill: sway.IBill) => {
            if (_bill.externalVersion) {
                return _bill.externalId + "v" + _bill.externalVersion;
            }
            return _bill.externalId;
        })(bill);
        return bill;
    };

    private addAdditionalAttributes = async (
        bill: sway.IBill
    ): Promise<sway.IBill> => {
        return await this.addBillScore(this.addFirestoreIdMethodToBill(bill));
    };

    public latestCreatedAt = async (): Promise<sway.IBill | void> => {
        const querySnapshot = await this.collection()
            .orderBy("createdAt", "desc")
            .limit(1)
            .get();
        if (!querySnapshot) return;

        const queryDocSnapshot = querySnapshot.docs[0];
        if (!queryDocSnapshot) return;

        return await this.addAdditionalAttributes(
            queryDocSnapshot.data() as sway.IBill
        );
    };

    private queryCategories = (categories: string[]) => {
        const query = this.collection().orderBy("createdAt", "desc");
        if (!isEmptyObject(categories)) {
            // `in` has a limit of 10 items
            return query.where("category", "in", categories).limit(10);
        }
        return query.limit(10);
    };

    public list = async (
        categories: string[] = []
    ): Promise<sway.IBill[] | void> => {
        const query = this.queryCategories(categories);

        const querySnapshot = await query.get();
        if (!querySnapshot) return;

        const bills = querySnapshot.docs;
        if (!bills) return;

        return Promise.all(
            bills.map((bill: any) => {
                return this.addAdditionalAttributes(
                    bill.data() as sway.IBill
                );
            })
        );
    };

    // fire.TypedDocumentReference<sway.IBill>
    private ref = (billFirestoreId: string): any => {
        return this.collection().doc(billFirestoreId);
    };

    private snapshot = async (
        billFirestoreId: string,
        options = {}
    ): Promise<fire.TypedDocumentSnapshot<sway.IBill>> => {
        return this.ref(billFirestoreId).get(options);
    };

    public get = async (
        billFirestoreId: string
    ): Promise<sway.IBill | void> => {
        const snap = await this.snapshot(billFirestoreId);
        if (!snap) return;

        return await this.addAdditionalAttributes(snap.data() as sway.IBill);
    };

    public create = async (billFirestoreId: string, data: sway.IBill) => {
        const now = this.firestoreConstructor.FieldValue.serverTimestamp();

        return this.ref(billFirestoreId).set({
            createdAt: now,
            updatedAt: now,
            ...data,
        });
    };

    public update = async (
        userVote: sway.IUserVote,
        data: sway.IPlainObject
    ): Promise<sway.IBillOrgsUserVote | void> => {
        const { billFirestoreId } = userVote;
        return this.ref(billFirestoreId)
            .update(data)
            .then(async () => {
                const updatedBill: sway.IBill | void = await this.get(
                    billFirestoreId
                );
                if (!updatedBill) return;

                return {
                    bill: updatedBill,
                    userVote,
                };
            });
    };
}

export default FireBills;
