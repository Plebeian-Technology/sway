/** @format */

import { Collections } from "@sway/constants";
import { arrayUnion, increment } from "firebase/firestore";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireUserBillShares extends AbstractFireSway {
    uid: string | "total";

    constructor(
        firestore: any,
        locale: sway.ILocale | sway.IUserLocale | null | undefined,

        uid: string,
    ) {
        super(firestore, locale);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUserBillShare> => {
        return this.firestore
            .collection(Collections.UserBillShares)
            .doc(this?.locale?.name)
            .collection(this.uid) as fire.TypedCollectionReference<sway.IUserBillShare>;
    };

    private ref = (
        billFirestoreId: string,
    ): fire.TypedDocumentReference<sway.IUserBillShare> | undefined => {
        return this.collection().doc(billFirestoreId);
    };

    private snapshot = async (
        billFirestoreId: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.IUserBillShare> | undefined> => {
        const ref = this.ref(billFirestoreId);
        if (!ref) return;

        return ref.get();
    };

    public list = async (): Promise<sway.IUserBillShare[]> => {
        const snap = await this.collection().get();
        return snap.docs.map((doc) => doc.data());
    };

    public get = async (billFirestoreId: string): Promise<sway.IUserBillShare | undefined> => {
        const snap = await this.snapshot(billFirestoreId);
        if (!snap) return;

        return snap.data();
    };

    public create = async (data: sway.IUserBillShare): Promise<sway.IUserBillShare | undefined> => {
        const ref = this.ref(data.billFirestoreId);
        if (!ref) return;

        await ref.set(data).catch(this.logError);
        return data;
    };

    public update = async ({
        billFirestoreId,
        platform,
        uid,
    }: {
        billFirestoreId: string;
        platform: sway.TSharePlatform;
        uid: string;
    }): Promise<sway.IUserBillShare | void> => {
        const ref = this.ref(billFirestoreId);
        if (!ref) return;

        ref.update({
            [`platforms.${platform}`]: increment(1),
            // @ts-ignore
            uids: arrayUnion(uid),
        }).catch(this.logError);
    };

    public upsert = async ({
        billFirestoreId,
        platform,
        uid,
    }: {
        billFirestoreId: string;
        platform: sway.TSharePlatform;
        uid: string;
    }): Promise<sway.IUserBillShare | undefined> => {
        const ref = this.ref(billFirestoreId);
        if (!ref) {
            return this.create({
                platforms: {
                    [platform]: 1,
                },
                billFirestoreId,
                uids: [uid],
            });
        }

        return ref
            .update({
                [`platforms.${platform}`]: increment(1),
                // @ts-ignore
                uids: arrayUnion(uid),
            })
            .then(async () => {
                return this.get(billFirestoreId);
            })
            .catch(async (error) => {
                this.logError(error);
                return this.get(billFirestoreId);
            });
    };
}

export default FireUserBillShares;
