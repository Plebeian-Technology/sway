/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import FireBillScores from "./fire_bill_scores";
import { isEmptyObject } from "@sway/utils";

class FireBills extends AbstractFireSway {
    private collection = () => {
        return this.firestore
            .collection(Collections.BillsOfTheWeek)
            .doc(this?.locale?.name)
            .collection(Collections.BillsOfTheWeek);
    };

    public listen = (
        callback: (
            snapshot: fire.TypedQuerySnapshot<sway.IBill>,
        ) => Promise<undefined>,
        errorCallback?: (params?: any) => undefined,
    ) => {
        if (errorCallback) {
            return this.collection().onSnapshot({
                next: callback,
                error: errorCallback,
            });
        }
        return this.collection().onSnapshot({ next: callback });
    };

    private addBillScore = async (bill: sway.IBill): Promise<sway.IBill> => {
        const scorer = new FireBillScores(
            this.firestore,
            this?.locale,
            this.firestoreConstructor,
        );
        const score = await scorer.get(bill.firestoreId);
        if (!score) return bill;

        bill.score = score;
        return { ...bill };
    };
    private addFirestoreIdToBill = (bill: sway.IBill): sway.IBill => {
        return {
            ...bill,
            firestoreId: bill.externalVersion
                ? bill.externalId + "v" + bill.externalVersion
                : bill.externalId,
        };
    };

    private addAdditionalAttributes = async (
        bill: sway.IBill,
    ): Promise<sway.IBill> => {
        return await this.addBillScore(this.addFirestoreIdToBill(bill));
    };

    public ofTheWeek = async (): Promise<sway.IBill | undefined> => {
        const querySnapshot = await this.collection()
            .orderBy("createdAt", "desc")
            .where("active", "==", true)
            .limit(1)
            .get();
        if (!querySnapshot) return;

        const queryDocSnapshot = querySnapshot.docs[0];
        if (!queryDocSnapshot) return;

        return await this.addAdditionalAttributes(
            queryDocSnapshot.data() as sway.IBill,
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
        categories: string[] = [],
    ): Promise<sway.IBill[] | undefined> => {
        const query = this.queryCategories(categories);

        const querySnapshot = await query.get();
        if (!querySnapshot) return;

        const bills = querySnapshot.docs;
        if (!bills || isEmptyObject(bills)) return;

        return Promise.all(
            bills.map((bill: any) => {
                return this.addAdditionalAttributes(bill.data() as sway.IBill);
            }),
        );
    };

    // fire.TypedDocumentReference<sway.IBill>
    private ref = (billFirestoreId: string): any => {
        return this.collection().doc(billFirestoreId);
    };

    private snapshot = async (
        billFirestoreId: string,
        options = {},
    ): Promise<fire.TypedDocumentSnapshot<sway.IBill>> => {
        return this.ref(billFirestoreId).get(options);
    };

    public get = async (
        billFirestoreId: string,
    ): Promise<sway.IBill | undefined> => {
        const snap = await this.snapshot(billFirestoreId);
        if (!snap || !snap.exists) return;

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
        data: sway.IPlainObject,
    ): Promise<sway.IBillOrgsUserVote | undefined> => {
        const { billFirestoreId } = userVote;
        return this.ref(billFirestoreId)
            .update(data)
            .then(async () => {
                const updatedBill: sway.IBill | undefined = await this.get(
                    billFirestoreId,
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
