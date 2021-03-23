/** @format */

import { Collections } from "@sway/constants";
import { sway, fire } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import FireBills from "./fire_bills";
import { logDev } from "@sway/utils";

class FireUserVotes extends AbstractFireSway {
    uid: string;

    constructor(
        firestore: any,
        locale: sway.ILocale,
        firestoreConstructor: any,
        uid: string,
    ) {
        super(firestore, locale, firestoreConstructor);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUserVote> => {
        return this.firestore
            .collection(Collections.UserVotes)
            .doc(this?.locale?.name)
            .collection(
                this.uid,
            ) as fire.TypedCollectionReference<sway.IUserVote>;
    };

    private ref = (
        billFirestoreId: string,
    ): fire.TypedDocumentReference<sway.IUserVote> => {
        return this.collection().doc(billFirestoreId);
    };

    private snapshot = (
        billFirestoreId: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.IUserVote>> => {
        return this.ref(billFirestoreId).get();
    };

    public count = async (): Promise<number> => {
        return (await this.collection().get()).size;
    };

    public getAll = async (): Promise<sway.IUserVote[]> => {
        const snap = await this.collection().get();
        return snap.docs.map((doc) => doc.data());
    };

    public get = async (
        billFirestoreId: string,
    ): Promise<sway.IUserVote | undefined> => {
        const snap = await this.snapshot(billFirestoreId);
        if (!snap) return;

        return snap.data();
    };

    public create = async (
        billFirestoreId: string,
        support: "for" | "against",
    ): Promise<sway.IUserVote | undefined | string> => {
        logDev("insert new user vote");
        const [exists, existsmessage] = await this.exists(billFirestoreId);
        if (exists) return existsmessage;

        logDev("insert new user vote - find bill", billFirestoreId);
        const [bill, billmessage] = await this.bill(billFirestoreId);
        if (!bill) return billmessage;

        const ref = this.ref(billFirestoreId);

        logDev("insert new user vote - insert", billFirestoreId);
        const userVote: sway.IUserVote | undefined = await ref
            .set({
                billFirestoreId: billFirestoreId,
                support,
            })
            .then(() => {
                return {
                    billFirestoreId: billFirestoreId,
                    support,
                } as sway.IUserVote;
            });
        if (!userVote) return "failed to create user vote";
        return userVote;
    };

    private bill = async (
        billFirestoreId: string,
    ): Promise<[sway.IBill | null, string]> => {
        const firebills = new FireBills(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
        );
        const bill = await firebills.get(billFirestoreId);
        if (!bill) {
            return [
                null,
                "no bill found with external id - " + billFirestoreId,
            ];
        }
        return [bill, ""];
    };

    private exists = async (
        billFirestoreId: string,
    ): Promise<[boolean, string]> => {
        const existingVote = await this.get(billFirestoreId);
        if (existingVote) {
            logDev(
                "user vote already exists on bill external id", billFirestoreId
            );
            return [
                true,
                `user vote already exists on bill external id - ${billFirestoreId}`,
            ];
        }
        return [false, ""];
    };
}

export default FireUserVotes;
