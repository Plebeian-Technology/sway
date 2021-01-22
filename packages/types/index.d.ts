/** @format */

declare module "sway" {
    import firebase from "firebase/app";

    namespace sway {
        export interface IPlainObject {
            [key: string]: any;
        }

        type TSwayLevel = "National" | "Regional" | "Local";
        type TAlertLevel = "info" | "success" | "warning" | "error";

        interface ISwayNotification {
            level: TAlertLevel;
            title: string;
            message?: string;
            duration?: number;
        }

        export interface ICloudFunctionResponse {
            success: boolean;
            message: string;
            data: IPlainObject[] | IPlainObject;
        }

        export interface ILocale {
            city: string;
            region: string;
            regionCode: string;
            country: string;
            name: string; // ex. baltimore-maryland-united_states, <city>-<region>-<country>
            districts: number[];
        }

        export interface IUserLocale extends ILocale {
            district: number; // ex. 1
        }

        export interface IAdmin {
            isAdmin: true;
        }

        export interface IUserInvites {
            emails: string[];
        }

        export interface IUser {
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            email: string; // from firebase
            uid: string; // from firebase
            locales: IUserLocale[];
            isRegistrationComplete: boolean; // completed the post-signup registration process
            name: string;
            title?: string;
            address1: string;
            address2: string;
            city: string;
            region: string;
            regionCode: string;
            country: string;
            postalCode: string;
            postalCodeExtension: string;
            phone: string;
            creationTime: string;
            lastSignInTime: string;
            invitedBy?: string;
            isAnonymous?: boolean;
            isSwayConfirmed: boolean; // confirmed to reside at IUserLocale, typically this field will have the same value for all IUserLocales for an IUser
            isRegisteredToVote: boolean; // is registered to vote at IUserLocale, typically this field will have the same value for all IUserLocales for an IUser
        }

        export interface IUserSettings {
            uid: string;
            notificationFrequency: 0 | 1 | 2 | null;
            notificationType: 0 | 1 | 2 | null;
            hasCheckedSupportFab: boolean;
            messagingRegistrationToken?: string;
        }

        export interface IUserWithSettingsAdmin {
            user: IUser;
            settings: IUserSettings;
            isAdmin: boolean;
        }

        export interface IUserVote {
            id?: firebase.firestore.FieldValue;
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            billFirestoreId: string;
            support: string | null;
        }

        export interface ILegislatorVote {
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            externalLegislatorId: string;
            billFirestoreId: string;
            support: string;
        }

        export interface IVote {
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            date: Date;
            time: string;
            legislatorVotePaths: firebase.firestore.FieldValue;
        }

        export interface IBasicLegislator {
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            externalId: string; // ex. bioguide_id from congress.gov
            bioguideId: string; // formatted to standard from congress.gov
            level: TSwayLevel;
            active: boolean;
            link: string;
            email: string;
            district: number;
            title: string;
            first_name: string;
            last_name: string;
            phone: string;
            fax?: string;
            street: string;
            street2?: string;
            street3?: string;
            city: string;
            region: string;
            regionCode: string;
            zip: string;
            party: string;
            photoURL?: string;
            twitter?: string;
        }
        export interface ILegislator extends IBasicLegislator {
            full_name: string;
        }

        export interface IUserLegislatorScore {
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            externalLegislatorId: string;
            totalUserVotes: number;
            totalUnmatchedLegislatorVote: number; // votes where user has voted but not legislator
            totalUserLegislatorAbstained: number; // votes where both the user and legislator abstained
            totalUserLegislatorAgreed: number;
            totalUserLegislatorDisagreed: number;
            userLegislatorVotes: firebase.firestore.FieldValue | string[];
        }

        export interface IUserLegislatorVote {
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            billFirestoreId: string;
            externalLegislatorId: string;
            uid: string;
            userSupport: string;
            legislatorSupport: string;
        }

        export interface IBaseScore {
            for: firebase.firestore.FieldValue;
            against: firebase.firestore.FieldValue;
        }

        export interface IBillScore extends IBaseScore {
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            districts: { [key: number]: IBaseScore };
        }

        export type TBillChamber = "house" | "senate" | "council";

        export interface ISwayBillSummaries {
            sway: string;
            [key: string]: string;
        }

        interface IExternalSummary {
            text: string;
            source: string;
            billFirestoreId: string;
        }

        // Used by UI
        export interface IBill {
            createdAt?: firebase.firestore.FieldValue;
            updatedAt?: firebase.firestore.FieldValue;
            level: TSwayLevel;
            active: boolean;
            externalId: string; // ex. congress_bill_id from congress.gov
            externalVersion: string;
            firestoreId: string;
            title: string;
            link: string;
            summaries: ISwayBillSummaries;
            score: IBillScore;
            chamber: TBillChamber;
            sponsorExternalId: string;
            category:
                | "police"
                | "health"
                | "housing"
                | "infrastructure"
                | "political reform"
                | "civil rights"
                | "education"
                | "transportation";
            status: "passed" | "failed" | "committee" | "vetoed";
            votedate?: string;
            relatedBillIds?: any; // ex. opposite chamber bills
        }

        export interface IBillWithOrgs {
            bill: IBill;
            organizations?: IOrganization[];
        }
        export interface IBillOrgsUserVote extends IBillWithOrgs {
            userVote?: IUserVote;
        }
        export interface ILegislatorWithUserScore {
            legislator: ILegislator;
            score?: IUserLegislatorScore;
        }

        export interface IOrganization {
            name: string;
            iconPath?: string;
            positions: IOrganizationPositions;
        }
        export interface IOrganizationPositions {
            [billFirestoreId: string]: IOrganizationPosition;
        }
        export interface IOrganizationPosition {
            billFirestoreId: string;
            support: boolean;
            summary: string;
        }

        export type TFormFieldPossibleValues = { label: string; value: string }[] | string[];

        export interface IFormField {
            name: string;
            type: "text" | "tel" | "number" | "boolean";
            component:
                | "text"
                | "select"
                | "textarea"
                | "generatedText"
                | "checkbox";
            label: string;
            isRequired: boolean;
            default?: string | null;
            possibleValues?: TFormFieldPossibleValues;
            disabled?: boolean;
            generateFields?: string[];
            joiner?: string;
            multi?: true;
        }

        export interface IAppState {
            bills: {
                billOfTheWeek: sway.IBill;
                userVoteOfTheWeek: sway.IUserVote;
                organizationsOfTheWeek: sway.IOrganization[];
                bills: sway.IBillWithOrgs[];
            };
            user: sway.IUserWithSettingsAdmin & {
                inviteUid: string;
                userLocales: sway.IUserLocale[];
            };
            legislators: {
                representatives: sway.ILegislatorWithUserScore[];
                legislators: sway.ILegislator[];
                isActive: boolean;
            };
            notification: { notification: sway.ISwayNotification };
        }
    }

    namespace fire {
        export interface TypedDocumentData<
            T extends firebase.firestore.DocumentData
        > extends firebase.firestore.DocumentData {
            [field: string]: T;
        }

        export interface TypedDocumentReference<
            T extends firebase.firestore.DocumentData
        > extends firebase.firestore.DocumentReference {
            readonly parent: TypedCollectionReference<T>;
            readonly path: string;

            orderBy(key: string, direction: string | undefined): TypedQuery<T>;

            collection(collectionPath: string): TypedCollectionReference<T>;

            isEqual(other: TypedDocumentReference<T>): boolean;

            set(
                data: T,
                options?: firebase.firestore.SetOptions,
            ): Promise<void>;

            update(data: Partial<T>): Promise<void>;

            update(
                field: keyof T | firebase.firestore.FieldPath,
                value: T[keyof T],
                ...moreFieldsAndValues: T[keyof T][]
            ): Promise<void>;

            delete(): Promise<void>;

            get(
                options?: firebase.firestore.GetOptions,
            ): Promise<TypedDocumentSnapshot<T>>;

            onSnapshot(params: any): any;

            // onSnapshot(observer: {
            //     next?: (snapshot: TypedDocumentSnapshot<T>) => void;
            //     error?: (error: firebase.firestore.FirestoreError) => void;
            //     complete?: () => void;
            // }): () => void;

            // onSnapshot(
            //     options: firebase.firestore.SnapshotListenOptions,
            //     observer: {
            //         next?: (snapshot: TypedDocumentSnapshot<T>) => void;
            //         error?: (error: Error) => void;
            //         complete?: () => void;
            //     }
            // ): () => void;

            // onSnapshot(
            //     onNext: (snapshot: TypedDocumentSnapshot<T>) => void,
            //     onError?: (error: Error) => void,
            //     onCompletion?: () => void
            // ): () => void;

            // onSnapshot(
            //     options: firebase.firestore.SnapshotListenOptions,
            //     onNext: (snapshot: TypedDocumentSnapshot<T>) => void,
            //     onError?: (error: Error) => void,
            //     onCompletion?: () => void
            // ): () => void;
        }

        export interface TypedDocumentSnapshot<
            T extends firebase.firestore.DocumentData
        > extends firebase.firestore.DocumentSnapshot {
            data(options?: firebase.firestore.SnapshotOptions): T | undefined;
            exists: boolean;
            ref: TypedDocumentReference<T>;
        }

        export interface TypedQuery<T extends TypedDocumentData<T>>
            extends firebase.firestore.Query {
            get(
                options?: firebase.firestore.GetOptions,
            ): Promise<TypedQuerySnapshot<T>>;

            where(
                fieldPath: keyof T | firebase.firestore.FieldPath,
                opStr: firebase.firestore.WhereFilterOp,
                value: T[keyof T],
            ): TypedQuery<T>;

            orderBy(key: string, direction: string | undefined): TypedQuery<T>;
            limit(limit: number): TypedQuery<T>;
        }

        export interface TypedQueryDocumentSnapshot<
            T extends firebase.firestore.DocumentData
        > extends firebase.firestore.QueryDocumentSnapshot {
            data(options?: firebase.firestore.SnapshotOptions): T;
            exists: boolean;
            ref: TypedDocumentReference<T>;
        }

        export interface TypedQuerySnapshot<
            T extends firebase.firestore.DocumentData
        > extends firebase.firestore.QuerySnapshot {
            docs: TypedQueryDocumentSnapshot<T>[];
            size: number;
            query: TypedQuery<T>;
        }

        export interface TypedCollectionReference<
            T extends firebase.firestore.DocumentData
        > extends firebase.firestore.CollectionReference {
            get(
                options?: firebase.firestore.GetOptions,
            ): Promise<TypedQuerySnapshot<T>>;

            where(
                fieldPath: keyof T | firebase.firestore.FieldPath,
                opStr: firebase.firestore.WhereFilterOp,
                value: T[keyof T],
            ): TypedQuery<T>;

            doc(documentPath?: string): TypedDocumentReference<T>;

            add(data: T): Promise<TypedDocumentReference<T>>;
        }

        class SwayFireClient {
            firestore: firebase.firestore.Firestore;
            locale: sway.IUserLocale;

            Locales(firestore: any): Promise<sway.ILocale[]>;

            bills(): any;
            billScores(): any;
            legislators(): any;
            legislatorVotes(): any;
            userLegislatorScores(): any;
            userDistrictScores(): any;
            users(): any;
            userSettings(): any;
            userInvites(): any;
            userVotes(): any;
            userScores(): any;
            userLegislatorVotes(): any;
        }
    }
}
