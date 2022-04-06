/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireOrganizations extends AbstractFireSway {
    private collection = (): fire.TypedCollectionReference<sway.IOrganization> => {
        return this.firestore
            .collection(Collections.Organizations)
            .doc(this?.locale?.name)
            .collection(
                Collections.Organizations,
            ) as fire.TypedCollectionReference<sway.IOrganization>;
    };

    private ref = (organization: string): fire.TypedDocumentReference<sway.IOrganization> => {
        return this.collection().doc(organization);
    };

    private snapshot = (
        organization: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.IOrganization> | void> => {
        return this.ref(organization).get().catch(this.logError);
    };

    // public list = async (): Promise<{ [organization_name: string]: sway.IOrganization } | undefined> => {
    public list = async (): Promise<sway.IOrganization[] | undefined> => {
        const snap: fire.TypedQuerySnapshot<sway.IOrganization> | void = await this.collection()
            .get()
            .catch(this.logError);
        if (!snap) {
            return;
        }

        const docs: fire.TypedQueryDocumentSnapshot<sway.IOrganization>[] = snap.docs.filter(
            (doc) => !!doc,
        );

        return docs.map((doc: fire.TypedDocumentSnapshot<sway.IOrganization>) =>
            doc.data(),
        ) as sway.IOrganization[];
    };

    public get = async (organization: string): Promise<sway.IOrganization | undefined> => {
        const snap = await this.snapshot(organization).catch(this.logError);
        if (!snap) return;

        return snap.data();
    };

    public create = async (data: sway.IOrganization) => {
        return this.ref(data.name).set(data).catch(this.logError);
    };

    public update = async (data: sway.IOrganization) => {
        return this.ref(data.name).update(data).catch(this.logError);
    };

    public listPositions = async (billFirestoreId: string): Promise<sway.IOrganization[]> => {
        const query: fire.TypedQuerySnapshot<sway.IOrganization> | void = await this.collection()
            .where(
                // @ts-ignore
                `positions.${billFirestoreId}.billFirestoreId`,
                "==",
                billFirestoreId,
            )
            .get()
            .catch(this.logError);

        if (!query) return [];

        const docs = query.docs.map((doc) => doc.data()).filter((doc: sway.IOrganization) => !!doc);

        return docs.map((doc: sway.IOrganization) => {
            return {
                ...doc,
                positions: {
                    [billFirestoreId]: doc.positions[billFirestoreId],
                },
            };
        });
    };

    public positions = async (
        organization: string,
    ): Promise<sway.IOrganizationPositions | undefined> => {
        const org: sway.IOrganization | undefined = await this.get(organization);
        if (!org) return;

        return org.positions;
    };

    public position = async (
        organization: string,
        billFirestoreId: string,
    ): Promise<sway.IOrganizationPosition | undefined> => {
        const org: sway.IOrganization | undefined = await this.get(organization);
        if (!org) return;

        return org.positions[billFirestoreId];
    };

    public addPosition = async (
        organization: string,
        billFirestoreId: string,
        position: sway.IOrganizationPosition,
    ) => {
        const positions = (await this.positions(organization)) || {};
        this.update({
            name: organization,
            positions: {
                ...positions,
                [billFirestoreId]: position,
            },
        }).catch(this.logError);
    };
}

export default FireOrganizations;
