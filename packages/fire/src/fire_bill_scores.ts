/** @format */

import { Collections } from "@sway/constants";
import { logDev } from "@sway/utils";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireBillScores extends AbstractFireSway {
    private collection = (): fire.TypedCollectionReference<sway.IBillScore> => {
        return this.firestore
            .collection(Collections.BillScores)
            .doc(this?.locale?.name)
            .collection(
                Collections.BillScores,
            ) as fire.TypedCollectionReference<sway.IBillScore>;
    };

    private ref = (
        billFirestoreId: string,
    ): fire.TypedDocumentReference<sway.IBillScore> => {
        return this.collection().doc(billFirestoreId);
    };

    public snapshot = async (
        billFirestoreId: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.IBillScore> | void> => {
        return this.ref(billFirestoreId).get().catch(this.logError);
    };

    public get = async (
        billFirestoreId: string,
    ): Promise<sway.IBillScore | undefined> => {
        const snap = await this.snapshot(billFirestoreId);
        if (!snap) return;

        return snap.data() as sway.IBillScore;
    };

    public create = async (
        billFirestoreId: string,
        data: { districts: sway.IPlainObject },
    ) => {
        const inc = this.firestoreConstructor.FieldValue.increment;
        const now = this.firestoreConstructor.FieldValue.serverTimestamp();

        const _data: sway.IBillScore = {
            createdAt: now,
            updatedAt: now,
            districts: data.districts,
            for: inc(0),
            against: inc(0),
        };
        return this.ref(billFirestoreId).set(_data).catch(this.logError);
    };

    public update = async (
        billFirestoreId: string,
        support: "for" | "against",
        district: string,
    ): Promise<sway.IBillScore | undefined> => {
        const ref = this.ref(billFirestoreId);
        if (!ref) return;

        const snap = await ref.get().catch(this.logError);
        if (!snap) return;

        const data = snap.data();
        if (!data) return;

        const inc = this.firestoreConstructor.FieldValue.increment;

        logDev(
            "Updating bill score with billFirestoreId - support - district:",
            billFirestoreId,
            support,
            district,
        );

        await ref
            .update({
                updatedAt:
                    this.firestoreConstructor.FieldValue.serverTimestamp(),
                [support]: inc(1),
            })
            .catch(this.logError);
        await ref
            .update({
                [`districts.${district}.${support}`]: inc(1),
            })
            .catch(this.logError);
        return this.get(billFirestoreId);
    };
}

export default FireBillScores;
