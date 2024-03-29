/** @format */

declare module "sway" {
    import firebase from "firebase/compat/app";

    namespace sway {
        export interface IPlainObject {
            [key: string]: any;
        }

        type TOption = { label: string; value: string | number };

        type TSwayLevel = "National" | "Regional" | "Local";
        type TAlertLevel = "info" | "success" | "warning" | "error";

        type TNotificationFrequency = 0 | 1 | 2;
        type TNotificationType = 0 | 1 | 2 | 3;

        type TAwardType = "Vote" | "BillShare" | "Invite" | "Sway";
        type TAwardColor = "blue" | "red" | "black" | "silver" | "gold";

        type TAwardByType = {
            [type in TAwardType]: {
                tooltip: (count: number, city: string) => string;
                nextTooltip: (nextCount: number, city: string) => string;
                icons: {
                    [path in TAwardColor]: string;
                };
            };
        };

        export interface ICloudFunctionResponse {
            success: boolean;
            message: string;
            data: Record<string, any>[] | Record<string, any>;
        }

        export interface ILocale {
            city: string;
            region: string;
            regionCode: string;
            country: string;
            name: string; // ex. baltimore-maryland-united_states, <city>-<region>-<country>
            districts: string[]; // ex. MD1
            icon: string;
            spreadsheetId?: string;
            timezone: string;
            currentSessionStartDate: string;
        }

        export interface IUserLocale extends ILocale {
            district: string; // ex. MD1
        }

        export interface IAdmin {
            isAdmin: true;
        }

        export interface ILocaleUsers extends ILocale {
            userCount: {
                all: firebase.firestore.FieldValue;
                [district: string]: firebase.firestore.FieldValue;
            };
        }

        export interface IUserInvites {
            sent: string[];
            redeemed: string[];
        }

        export interface IUser {
            createdAt?: Date;
            updatedAt?: Date;
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
            isEmailVerified: boolean;
        }

        export interface ICongratulationsSettings {
            isCongratulateOnUserVote: boolean;
            isCongratulateOnInviteSent: boolean;
            isCongratulateOnSocialShare: boolean;
        }

        export interface IUserSettings {
            uid: string;
            notificationFrequency: TNotificationFrequency;
            notificationType: TNotificationType;
            hasCheckedSupportFab: boolean;
            messagingRegistrationToken?: string;
            congratulations: ICongratulationsSettings;
        }

        export interface IUserWithSettings {
            user: IUser;
            settings: IUserSettings;
        }

        export interface IUserWithSettingsAdmin {
            user: IUser;
            settings: IUserSettings;
            isAdmin: boolean;
        }

        export interface IUserVote {
            createdAt?: Date;
            updatedAt?: Date;
            billFirestoreId: string;

            support: sway.TUserSupport | null;
        }

        export type TLegislatorSupport = "for" | "against" | "abstain" | null;
        export type TUserSupport = "for" | "against";

        export interface ILegislatorBillSupport {
            [externalLegislatorId: string]: sway.TLegislatorSupport;
        }

        export interface ILegislatorVote {
            createdAt?: Date;
            updatedAt?: Date;
            externalLegislatorId: string;
            billFirestoreId: string;
            support: TLegislatorSupport;
        }

        export interface IVote {
            createdAt?: Date;
            updatedAt?: Date;
            date: Date;
            time: string;
            legislatorVotePaths: firebase.firestore.FieldValue;
        }

        export interface IBasicLegislator {
            createdAt?: Date;
            updatedAt?: Date;
            externalId: string; // ex. bioguide_id from congress.gov
            level?: TSwayLevel;
            active: boolean;
            link: string;
            email: string;
            district: string; // ex. MD1
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

        export interface IUserLegislatorScoreV2 {
            countAgreed: number;
            countDisagreed: number;
            countNoLegislatorVote: number;
            countLegislatorAbstained: number;
        }

        export interface IBaseScore {
            for: firebase.firestore.FieldValue | number;
            against: firebase.firestore.FieldValue | number;
        }
        export interface IBillScoreDistrct {
            [district: string]: IBaseScore; // ex. MD1
        }

        export interface IBillScore extends IBaseScore {
            createdAt?: Date;
            updatedAt?: Date;
            districts: IBillScoreDistrct;
        }

        export interface IBillLocaleScore {
            billFirestoreId: string;
            agreedDistrict: number;
            disagreedDistrict: number;
            agreedAll: number;
            disagreedAll: number;
        }

        export interface ITotalBillLocaleScores {
            billFirestoreIds: string[];
            totalAgreedDistrict: number;
            totalDisagreedDistrict: number;
            totalAgreedAll: number;
            totalDisagreedAll: number;
        }

        export interface IBillLocaleUserCount {
            countAllUsersInLocale: number;
            countAllUsersInDistrict: number;
        }

        export interface IAggregatedBillLocaleScores extends ITotalBillLocaleScores {
            countAllUsersInLocale: number;
            countAllUsersInDistrict: number;
            externalLegislatorId: string;
            billScores: IBillLocaleScore[] | undefined;
        }

        export type TBillChamber = "house" | "senate" | "council" | "both";

        export interface ISwayBillSummaries {
            sway: string;
            swayAudioBucketPath?: string;
            swayAudioByline?: string;
            [key: string]: string;
        }

        interface IExternalSummary {
            text: string;
            source: string;
            billFirestoreId: string;
        }

        type TSharePlatform =
            | "facebook"
            | "whatsapp"
            | "twitter"
            | "reddit"
            | "linkedin"
            | "pintrest"
            | "telegram";
        interface ISharedPlatform {
            email?: number;
            facebook?: number;
            telegram?: number;
            twitter?: number;
            whatsapp?: number;
        }

        interface IUserBillShare {
            platforms: ISharedPlatform;
            billFirestoreId: string;
            uids: string[];
        }

        interface INotification {
            date: string;
        }

        interface IUserSway {
            countBillsShared: number; // if a user has shared a bill in any way
            countAllBillShares: number; // total number of ways in which a user has shared a bill
            countInvitesSent: number;
            countInvitesRedeemed: number;
            countBillsVotedOn: number;
            countFacebookShares: number;
            countTwitterShares: number;
            countTelegramShares: number;
            countWhatsappShares: number;
            countEmailShares: number;
            totalSway: number;
            uids: string[]; // can have duplicates
        }

        export type TBillStatus = "passed" | "failed" | "committee" | "vetoed";
        export type TBillCategory =
            | "police"
            | "health"
            | "housing"
            | "infrastructure"
            | "political reform"
            | "civil rights"
            | "education"
            | "economy"
            | "transportation";

        // Used by UI
        export interface IBill {
            createdAt?: Date;
            updatedAt?: Date;
            swayReleaseDate?: Date;
            active: boolean;
            level: TSwayLevel;
            externalId: string; // ex. congress_bill_id from congress.gov
            externalVersion: string;
            firestoreId: string;
            title: string;
            link: string;
            summaries: ISwayBillSummaries;
            swaySummary?: string;
            score: IBillScore;
            chamber: TBillChamber;
            sponsorExternalId: string;
            status: TBillStatus;
            introducedDate?: string;
            votedate?: string;
            houseVoteDate?: string;
            senateVoteDate?: string;
            relatedBillIds?: any; // ex. opposite chamber bills
            isTweeted: boolean;
            isInitialNotificationsSent: boolean;
            category: TBillCategory;

            supporters?: string[];
            opposers?: string[];
            abstainers?: string[];
        }

        export interface IBillWithOrgs {
            bill: IBill;
            organizations?: IOrganization[];
        }
        export interface IBillOrgsUserVote extends IBillWithOrgs {
            userVote?: IUserVote;
        }

        export interface IBillOrgsUserVoteScore extends IBillOrgsUserVote {
            score?: IBillScore;
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

        export interface IFormField {
            name: string;
            subLabel?: string;
            type: "text" | "email" | "tel" | "number" | "boolean" | "date";
            component: "text" | "select" | "textarea" | "generatedText" | "checkbox" | "date";
            label: string;
            isRequired: boolean;
            default?: string | null;
            possibleValues?: sway.TOption[];
            disabled?: boolean;
            generateFields?: string[];
            joiner?: string;
            multi?: true;
            createable?: true;
            autoComplete?: string;
            helperText?: string;
            rows?: number;
            disableOn?: (values: any) => boolean;
            colClass?: number;
            containerClassName?: string;
        }

        export interface IAppState {
            user: sway.IUserWithSettingsAdmin & {
                inviteUid: string;
                isEmailVerifiedRedux: boolean;
                userLocales: sway.IUserLocale[];
            };
            locale: sway.ILocale | sway.IUserLocale | undefined;
            // legislators: {
            //     legislators: sway.ILegislator[];
            // };
        }
    }

    namespace fire {
        export interface TypedDocumentData<T extends firebase.firestore.DocumentData>
            extends firebase.firestore.DocumentData {
            [field: string]: T;
        }

        export interface TypedDocumentReference<T extends firebase.firestore.DocumentData>
            extends firebase.firestore.DocumentReference {
            readonly parent: TypedCollectionReference<T>;
            readonly path: string;

            // orderBy(key: string, direction: string | undefined): TypedQuery<T>;

            collection(collectionPath: string): TypedCollectionReference<T>;

            isEqual(other: TypedDocumentReference<T>): boolean;

            set(data: T, options?: firebase.firestore.SetOptions): Promise<void>;

            update(data: Partial<T>): Promise<void>;

            update(
                field: keyof T | firebase.firestore.FieldPath,
                value: T[keyof T],
                ...moreFieldsAndValues: T[keyof T][]
            ): Promise<void>;

            delete(): Promise<void>;

            get(options?: firebase.firestore.GetOptions): Promise<TypedDocumentSnapshot<T>>;

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

        export interface TypedDocumentSnapshot<T extends firebase.firestore.DocumentData>
            extends firebase.firestore.DocumentSnapshot {
            data(options?: firebase.firestore.SnapshotOptions): T;
            get(
                fieldPath: string | firebase.firestore.FieldPath,
                options?: firebase.firestore.SnapshotOptions,
            ): any;
            isEqual(other: firebase.firestore.DocumentSnapshot<T>): boolean;
            exists: boolean;
            ref: TypedDocumentReference<T>;
            metadata: firebase.firestore.SnapshotMetadata;
            id: string;
        }

        export interface TypedQuery<T extends TypedDocumentData<T>>
            extends firebase.firestore.Query {
            get(options?: firebase.firestore.GetOptions): Promise<TypedQuerySnapshot<T>>;

            where(
                fieldPath: keyof T | firebase.firestore.FieldPath,
                opStr: firebase.firestore.WhereFilterOp,
                value: T[keyof T],
            ): TypedQuery<T>;

            orderBy(key: string, direction: string | undefined): TypedQuery<T>;
            limit(limit: number): TypedQuery<T>;
        }

        export interface TypedQueryDocumentSnapshot<T extends firebase.firestore.DocumentData>
            extends firebase.firestore.QueryDocumentSnapshot {
            data(options?: firebase.firestore.SnapshotOptions): T;
            get(
                fieldPath: string | firebase.firestore.FieldPath,
                options?: firebase.firestore.SnapshotOptions,
            ): any;
            isEqual(other: firebase.firestore.DocumentSnapshot<T>): boolean;
            exists: boolean;
            ref: TypedDocumentReference<T>;
            metadata: firebase.firestore.SnapshotMetadata;
            id: string;
        }

        export interface TypedQuerySnapshot<T extends firebase.firestore.DocumentData>
            extends firebase.firestore.QuerySnapshot {
            docs: TypedQueryDocumentSnapshot<T>[];
            size: number;
            query: TypedQuery<T>;
            metadata: firebase.firestore.SnapshotMetadata;
        }

        export interface TypedCollectionReference<T extends firebase.firestore.DocumentData>
            extends firebase.firestore.CollectionReference {
            get(options?: firebase.firestore.GetOptions): Promise<TypedQuerySnapshot<T>>;

            where(
                fieldPath: keyof T | firebase.firestore.FieldPath,
                opStr: firebase.firestore.WhereFilterOp,
                value: T[keyof T],
            ): TypedQuery<T>;

            doc(documentPath?: string): TypedDocumentReference<T>;

            add(data: T): Promise<TypedDocumentReference<T>>;
        }

        class SwayFireClient {
            firestore: any; // firebase.firestore.Firestore;
            locale: sway.ILocale | null;

            name(): string | undefined;
            bills(): any;
            billScores(): any;
            legislators(): any;
            legislatorVotes(): any;
            locales(): any;
            users(): any;
            userBillShares(): any;
            userSettings(): any;
            userInvites(): any;
            userVotes(): any;
            organizations(): any;
            notifications(): any;
        }
    }
}
