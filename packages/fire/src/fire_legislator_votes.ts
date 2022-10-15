/** @format */

import { Collections } from "@sway/constants";
import { serverTimestamp } from "firebase/firestore";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireLegislatorVotes extends AbstractFireSway {
    private collection = (
        externalLegislatorId: string,
    ): fire.TypedCollectionReference<sway.ILegislatorVote> => {
        return this.firestore
            .collection(Collections.LegislatorVotes)
            .doc(this?.locale?.name)
            .collection(
                externalLegislatorId,
            ) as fire.TypedCollectionReference<sway.ILegislatorVote>;
    };

    private ref = (
        externalLegislatorId: string,
        billFirestoreId: string,
    ): fire.TypedDocumentReference<sway.ILegislatorVote> => {
        return this.collection(externalLegislatorId).doc(billFirestoreId);
    };

    private snapshot = (
        externalLegislatorId: string,
        billFirestoreId: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.ILegislatorVote> | void> => {
        return this.ref(externalLegislatorId, billFirestoreId).get().catch(this.logError);
    };

    public exists = async (
        externalLegislatorId: string,
        billFirestoreId: string,
    ): Promise<boolean> => {
        return (await this.ref(externalLegislatorId, billFirestoreId).get()).exists;
    };

    public get = async (
        externalLegislatorId: string,
        billFirestoreId: string,
    ): Promise<sway.ILegislatorVote | undefined> => {
        const snap = await this.snapshot(externalLegislatorId, billFirestoreId).catch(
            this.logError,
        );
        if (!snap) return;

        return snap.data();
    };

    public getAll = async (externalLegislatorId: string): Promise<sway.ILegislatorVote[]> => {
        const votes = await this.collection(externalLegislatorId)
            .get()
            .then((snap) => {
                return snap.docs.map((doc) => doc.data());
            })
            .catch(this.logError);
        if (!votes) return [];

        return votes.filter(Boolean);
    };

    public create = async (
        externalLegislatorId: string,
        billFirestoreId: string,
        support: "for" | "against" | "abstain",
    ): Promise<sway.ILegislatorVote | void> => {
        return this.ref(externalLegislatorId, billFirestoreId)
            .set({
                createdAt: serverTimestamp(),
                updatedAt: serverTimestamp(),
                externalLegislatorId,
                billFirestoreId,
                support,
            })
            .then(() => this.get(externalLegislatorId, billFirestoreId))
            .catch(this.logError);
    };

    public updateSupport = async (
        externalLegislatorId: string,
        billFirestoreId: string,
        support: "for" | "against" | "abstain",
    ): Promise<sway.ILegislatorVote | void> => {
        return this.ref(externalLegislatorId, billFirestoreId)
            .update({
                updatedAt: serverTimestamp(),
                support,
            })
            .then(() => this.get(externalLegislatorId, billFirestoreId))
            .catch(this.logError);
    };
}

export default FireLegislatorVotes;
