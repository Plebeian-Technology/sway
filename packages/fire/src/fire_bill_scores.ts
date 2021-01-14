/** @format */

import { Collections, Support } from "@sway/constants";
import { sway, fire } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireBillScores extends AbstractFireSway {
    private collection = (): fire.TypedCollectionReference<
        sway.IBillScore
    > => {
        return this.firestore
            .collection(Collections.BillScores)
            .doc(this?.locale?.name)
            .collection(
                Collections.BillScores
            ) as fire.TypedCollectionReference<sway.IBillScore>;
    };

    private ref = (
        billFirestoreId: string
    ): fire.TypedDocumentReference<sway.IBillScore> => {
        return this.collection().doc(billFirestoreId);
    };

    private snapshot = (
        billFirestoreId: string
    ): Promise<fire.TypedDocumentSnapshot<sway.IBillScore>> | void => {
        return this.ref(billFirestoreId).get();
    };

    public get = async (
        billFirestoreId: string
    ): Promise<sway.IBillScore | void> => {
        const snap = await this.snapshot(billFirestoreId);
        if (!snap) return;

        return snap.data() as sway.IBillScore;
    };

    public create = async (
        billFirestoreId: string,
        data: { districts: sway.IPlainObject }
    ) => {
        const inc = this.firestoreConstructor.FieldValue.increment;
        const now = this.firestoreConstructor.FieldValue.serverTimestamp();

        try {
            const _data: sway.IBillScore = {
                createdAt: now,
                updatedAt: now,
                districts: data.districts,
                for: inc(0),
                against: inc(0),
            };
            return this.ref(billFirestoreId).set(_data);
        } catch (error) {
            throw new Error(
                `Error creating bill score from data - ${data}.\n\nError from firebase - ${error}`
            );
        }
    };

    public update = async (billFirestoreId: string, support: string) => {
        const ref = this.ref(billFirestoreId);
        if (!ref) return;

        const snap = await ref.get();
        if (!snap) return;

        const data = snap.data();
        if (!data) return;

        const inc = this.firestoreConstructor.FieldValue.increment;

        const field = support === Support.For ? Support.For : Support.Against;

        return ref.update({
            ...data,
            updatedAt: this.firestoreConstructor.FieldValue.serverTimestamp(),
            [field]: inc(1),
        });
    };

    public updateDistrictScores = async(billFirestoreId: string, support: string, district: number) => {
        const ref = this.ref(billFirestoreId);
        if (!ref) return;

        const snap = await ref.get();
        if (!snap) return;

        const data = snap.data();
        if (!data) return;

        const inc = this.firestoreConstructor.FieldValue.increment;

        return ref.update({
            ...data,
            updatedAt: this.firestoreConstructor.FieldValue.serverTimestamp(),
            districts: {
                ...data.districts,
                [district]: {
                    for: support === Support.For ? inc(1) : inc(0),
                    against: support === Support.Against ? inc(1) : inc(0),
                }
            }
        });
    }
}

export default FireBillScores;
