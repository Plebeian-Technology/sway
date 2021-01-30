/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireUserBillShares extends AbstractFireSway {
    uid: string;

    constructor(
        firestore: any,
        locale: sway.ILocale | sway.IUserLocale | null | undefined,
        firestoreConstructor: any,
        uid: string,
    ) {
        super(firestore, locale, firestoreConstructor);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUserBillShare> => {
        return this.firestore
            .collection(Collections.UserBillShares)
            .doc(this?.locale?.name)
            .collection(
                this.uid,
            ) as fire.TypedCollectionReference<sway.IUserBillShare>;
    };

    private ref = (
        billFirestoreId: string,
    ): fire.TypedDocumentReference<sway.IUserBillShare> | undefined => {
        return this.collection().doc(billFirestoreId);
    };

    private snapshot = async (
        billFirestoreId: string,
    ): Promise<
        fire.TypedDocumentSnapshot<sway.IUserBillShare> | undefined
    > => {
        const ref = this.ref(billFirestoreId);
        if (!ref) return;

        return ref.get();
    };

    public list = async(): Promise<sway.IUserBillShare[]> => {
        const snap = await this.collection().get();
        return snap.docs.map((doc) => doc.data());
    };

    public get = async (
        billFirestoreId: string,
    ): Promise<sway.IUserBillShare | undefined> => {
        const snap = await this.snapshot(billFirestoreId);
        if (!snap) return;

        return snap.data() as sway.IUserBillShare;
    };

    public upsert = async (data: sway.IUserBillShare) => {
        const ref = this.ref(data.billFirestoreId);
        if (!ref) return;

        const snap = await ref.get();
        if (!snap.exists) {
            return this.create(data);
        }
        return this.update(data);
    };

    public create = async (
        data: sway.IUserBillShare,
    ): Promise<sway.IUserBillShare | undefined> => {
        const ref = this.ref(data.billFirestoreId);
        if (!ref) return;

        await ref.set(data).catch(console.error);
        return data;
    };

    public update = async (
        data: sway.IUserBillShare,
    ): Promise<sway.IUserBillShare | void> => {
        const ref = this.ref(data.billFirestoreId);
        if (!ref) return;
        const current = (await ref.get()).data();
        if (!current) return;

        const platforms = current.platforms;
        const newPlatforms = {
            ...platforms,
            ...data.platforms,
        };
        data.platforms = newPlatforms;

        return ref.update({
            ...current,
            ...data,
        });
    };
}

export default FireUserBillShares;
