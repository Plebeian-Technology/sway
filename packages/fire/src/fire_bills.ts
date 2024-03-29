/** @format */

import { Collections } from "@sway/constants";
import { isEmptyObject } from "@sway/utils";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import FireBillScores from "./fire_bill_scores";

class FireBills extends AbstractFireSway {
    public collection = () => {
        return this.firestore
            .collection(Collections.BillsOfTheWeek)
            .doc(this?.locale?.name)
            .collection(Collections.BillsOfTheWeek);
    };

    private addBillScore = async (bill: sway.IBill): Promise<sway.IBill> => {
        const scorer = new FireBillScores(
            this.firestore,
            this?.locale,
            this.firestoreConstructor,
            this.logger,
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
                ? `${bill.externalId}v${bill.externalVersion}`
                : bill.externalId,
        };
    };

    private addAdditionalAttributes = async (bill: sway.IBill): Promise<sway.IBill> => {
        return this.addBillScore(this.addFirestoreIdToBill(bill));
    };

    public ofTheWeek = async (): Promise<sway.IBill | undefined> => {
        const querySnapshot = await this.collection()
            .orderBy("swayReleaseDate", "desc")
            .where("active", "==", true)
            .where("swayReleaseDate", "!=", false) // != operator - https://firebase.google.com/docs/firestore/query-data/queries#not_equal_
            .where("swayReleaseDate", "<", new Date())
            .limit(1)
            .get();
        if (!querySnapshot) return;

        const queryDocSnapshot = querySnapshot.docs[0];
        if (!queryDocSnapshot) return;

        return this.addAdditionalAttributes(queryDocSnapshot.data() as sway.IBill);
    };

    private queryCategories = (categories: string[]) => {
        const query = this.collection()
            .orderBy("swayReleaseDate", "desc") // != operator - https://firebase.google.com/docs/firestore/query-data/queries#not_equal_
            .where("active", "==", true)
            .where("swayReleaseDate", "!=", false); // != operator - https://firebase.google.com/docs/firestore/query-data/queries#not_equal_

        if (!isEmptyObject(categories)) {
            // `in` has a limit of 10 items
            return query.where("category", "in", categories).limit(10);
        }
        return query.limit(10);
    };

    public where = (key: string, operator: string, value: any): fire.TypedQuery<any> => {
        return this.collection().where(key, operator, value) as fire.TypedQuery<any>;
    };

    public list = async (categories: string[] = []): Promise<sway.IBill[] | undefined> => {
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

    public ref = (billFirestoreId: string): fire.TypedDocumentReference<sway.IBill> | undefined => {
        if (!billFirestoreId) return;
        return this.collection().doc(billFirestoreId);
    };

    private snapshot = async (
        billFirestoreId: string,
        options = {},
    ): Promise<fire.TypedDocumentSnapshot<sway.IBill> | void> => {
        const ref = this.ref(billFirestoreId);
        if (ref) {
            return ref.get(options).catch(this.logError);
        }
    };

    public get = async (billFirestoreId: string): Promise<sway.IBill | undefined> => {
        const snap = await this.snapshot(billFirestoreId).catch(this.logError);
        if (!snap || !snap.exists) return;

        return this.addAdditionalAttributes(snap.data());
    };

    public create = async (
        billFirestoreId: string,
        data: sway.IBill,
    ): Promise<sway.IBill | undefined> => {
        const now = new Date();
        const future = new Date();
        future.setFullYear(future.getFullYear() + 1);

        const newBill = {
            swayReleaseDate: future,
            createdAt: now,
            updatedAt: now,
            ...data,
        };
        const ref = this.ref(billFirestoreId);
        if (ref) {
            return ref
                .set(newBill)
                .then(() => newBill)
                .catch((e) => {
                    this.logError(e);
                    return undefined;
                });
        } else {
            return undefined;
        }
    };

    public update = async (
        userVote: sway.IUserVote,
        data: Partial<sway.IBill>,
    ): Promise<sway.IBillOrgsUserVote | undefined | void> => {
        const billFirestoreId = data.firestoreId || userVote.billFirestoreId;
        const ref = this.ref(billFirestoreId);
        if (ref) {
            return ref
                .update(data)
                .then(async () => {
                    const updatedBill: sway.IBill | undefined = await this.get(billFirestoreId);
                    if (!updatedBill) return;

                    return {
                        bill: updatedBill,
                        userVote,
                    };
                })
                .catch(this.logError);
        }
    };
}

export default FireBills;
