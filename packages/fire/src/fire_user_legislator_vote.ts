/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireUserLegislatorVotes extends AbstractFireSway {
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

    private collection = (): fire.TypedCollectionReference<sway.IUserLegislatorVote> => {
        return this.firestore
            .collection(Collections.UserLegislatorVotes)
            .doc(this?.locale?.name)
            .collection(
                this.uid,
            ) as fire.TypedCollectionReference<sway.IUserLegislatorVote>;
    };

    public ref = (
        billFirestoreId: string,
    ): fire.TypedDocumentReference<sway.IUserLegislatorVote> => {
        return this.collection().doc(billFirestoreId);
    };

    private snapshot = (
        billFirestoreId: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.IUserLegislatorVote>> => {
        return this.ref(billFirestoreId).get();
    };

    public exists = async (billFirestoreId: string): Promise<boolean> => {
        return (await this.snapshot(billFirestoreId)).exists;
    };

    public get = async (billFirestoreId: string): Promise<sway.IUserLegislatorVote | undefined> => {
        return (await this.snapshot(billFirestoreId)).data();
    };

    public create = async (
        userSupport: string,
        legislatorSupport: string | undefined,
        billFirestoreId: string,
        externalLegislatorId: string,
    ): Promise<fire.TypedDocumentReference<sway.IUserLegislatorVote> | undefined> => {
        const ref = this.ref(billFirestoreId);
        const snap = await this.snapshot(billFirestoreId);

        // legislatorSupport CANNOT be falsey
        if (snap.exists) {
            if (!legislatorSupport) return;
            return ref
                .update({
                    billFirestoreId,
                    externalLegislatorId,
                    userSupport,
                    legislatorSupport,
                    uid: this.uid,
                })
                .then(() => ref);
        }

        // legislatorSupport CAN be falsey
        return ref
            .set({
                billFirestoreId,
                externalLegislatorId,
                userSupport,
                legislatorSupport: legislatorSupport || "",
                uid: this.uid,
            })
            .then(() => ref);
    };
}

export default FireUserLegislatorVotes;
