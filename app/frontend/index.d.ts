/** @format */

declare module "sway" {
    // https://stackoverflow.com/a/75201302/6410635
    type EitherOnly<T, U> = {
        [P in keyof T]: T[P];
    } & {
        [P in keyof U]?: never;
    };
    type Either<T, U> = EitherOnly<T, U> | EitherOnly<U, T>;

    // https://dev.to/maxime1992/implement-a-generic-oneof-type-with-typescript-22em
    // type OneOf<Obj, Key extends keyof Obj> = { [key in Exclude<keyof Obj, Key>]: null } & Pick<Obj, Key>;

    // https://stackoverflow.com/a/65420892/6410635
    // type KeyOf<T extends Record<string, any>> = Extract<keyof T, string>;
    type KeyOf<T> = Extract<keyof T, string>;
    type KeyOfOmit<T, K> = Omit<Extract<keyof T, string>, K>;

    // https://stackoverflow.com/a/49286056/6410635
    type ValueOf<T> = T[keyof T];

    interface IIDObject {
        id: number;
    }

    // Type recursion error - https://stackoverflow.com/a/70552078/6410635
    // type PathImpl<T, K extends keyof T, A extends string[] = []> = A["length"] extends 5
    //     ? never
    //     : K extends string
    //       ? T[K] extends Record<string, string>
    //           ? T[K] extends ArrayLike<string>
    //               ? K | `${K}.${PathImpl<T[K], Exclude<keyof T[K], keyof string[]>, Increment<A>>}`
    //               : K | `${K}.${PathImpl<T[K], keyof T[K], Increment<A>>}`
    //           : K
    //       : never;
    // type Path<T> = PathImpl<T, keyof T> | Extract<keyof T, string>;

    // Fixes the above
    // https://stackoverflow.com/a/58436959/6410635
    type Path<T> = T extends object
        ? { [K in keyof T]: `${Exclude<K, symbol>}${"" | `.${Paths<T[K]>}`}` }[keyof T]
        : never;

    interface ISelectOption {
        label: string;
        value: string | number;
    }

    namespace sway {
        interface IValidationResult {
            success: boolean;
            message: string;
            data?: Record<string, any>;
        }

        interface IPageProps extends Record<string, unknown> {
            user: sway.IUser;
            sway_locale: sway.ISwayLocale;
            sway_locales: sway.ISwayLocale[];
        }

        namespace awards {
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
        }

        type TAlertLevel = "info" | "success" | "warning" | "error";

        type TNotificationFrequency = 0 | 1 | 2;
        type TNotificationType = 0 | 1 | 2 | 3;

        type TParty = "D" | "R" | "I" | "X";

        interface ICloudFunctionResponse {
            success: boolean;
            message: string;
            data: Record<string, any>[] | Record<string, any>;
        }

        interface IAddress extends IIDObject {
            street: string;
            street2?: string;
            street3?: string;
            city: string;
            region_code: string;
            country: string;
            postal_code: string;
            full_address: string;
            latitude: number;
            longitude: number;
        }

        interface IDistrict extends IIDObject {
            name: string;
            number: number;
            region_code: string;
            // sway_locale: ISwayLocale;
        }

        interface ISwayLocale extends IIDObject {
            name: string; // ex. baltimore-maryland-united_states, <city>-<region>-<country>
            city: string;
            region_code: string;
            region_name: string;
            country: string;
            // districts: IDistrict[];
            icon_path: string;
            time_zone: string;
            current_session_start_date: string;
        }

        interface IAdmin {
            is_admin: true;
        }

        interface ISwayLocaleUsers extends ISwayLocale {
            userCount: {
                all: number;
                [district: string]: number;
            };
        }

        interface IUserInvite extends IIDObject {
            user: IUser;
            invitee_email: string;
            invite_accepted_on_utc: Date;
            invite_expires_on_utc: Date;
        }

        interface IUser extends IIDObject {
            id: number;
            // name: string;
            full_name?: string;
            email: string | null;
            phone: string;
            invite_url: string | null;
            is_registration_complete: boolean; // completed the post-sign_up registration process
            is_registered_to_vote: boolean; // is registered to vote at ISwayLocale, typically this field will have the same value for all ISwayLocales for an IUser
            is_email_verified: boolean;
            is_phone_verified: boolean;
            is_sway_confirmed: boolean; // confirmed to reside at ISwayLocale, typically this field will have the same value for all ISwayLocales for an IUser
            address: IAddress;
            locales: ISwayLocale[];
            is_admin?: boolean;
        }

        interface IApiUserVote {
            id: number;
            bill_id: number;
            user_id: number;
            support: sway.TUserSupport;
            updated_at: string;
            created_at: string;
        }

        interface IUserVote {
            bill: IBill;
            user: IUser;
            support: sway.TUserSupport | undefined;
        }

        type TLegislatorSupport = "FOR" | "AGAINST" | "ABSTAIN" | null;
        type TUserSupport = "FOR" | "AGAINST";

        interface ILegislatorVote extends IIDObject {
            legislator_id: number;
            bill_id: number;
            support: TLegislatorSupport;
        }

        interface ILegislatorBillSupport {
            [external_legislator_id: string]: sway.TLegislatorSupport;
        }

        interface ILegislatorVote {
            legislator: ILegislator;
            bill: IBill;
            support: TLegislatorSupport;
        }

        interface ILegislator extends IIDObject {
            sway_locale_id: number;
            party: TParty;
            title: string;
            first_name: string;
            last_name: string;
            full_name: string;
            external_id: string; // ex. bioguide_id from congress.gov
            active: boolean;
            link: string;
            email: string;
            district: IDistrict;
            phone: string;
            fax?: string;
            address?: IAddress;
            photo_url?: string;
            twitter?: string;
        }

        interface IBaseScore {
            for: number;
            against: number;
        }
        interface IBillScoreDistrct extends IBaseScore {
            district: IDistrict;
        }

        interface IBillScore extends IBaseScore {
            bill_id: number;
            districts: IBillScoreDistrct[];
        }

        interface IBillLocaleScore {
            bill_id: number;
            agreed_district: number;
            disagreed_district: number;
            agreed_all: number;
            disagreed_all: number;
        }

        interface IBillLocaleUserCount {
            countAllUsersInLocale: number;
            count_all_users_in_district: number;
        }

        interface IAggregatedBillLocaleScores {
            count_all_users_in_locale: number;
            count_all_users_in_district: number;
            external_legislator_id: string;
            bill_scores: IBillLocaleScore[] | undefined;
        }

        type TBillChamber = "house" | "senate" | "council" | "both";

        interface ISwayBillSummaries {
            sway: string;
            audio_bucket_path?: string;
            audio_by_line?: string;

            // [key: string]: string;
        }

        interface IExternalSummary {
            text: string;
            source: string;
            bill_external_id: string;
        }

        type TSharePlatform = "facebook" | "whatsapp" | "twitter" | "reddit" | "linkedin" | "pintrest" | "telegram";
        interface ISharedPlatform {
            email?: number;
            facebook?: number;
            telegram?: number;
            twitter?: number;
            whatsapp?: number;
        }

        interface IUserBillShare {
            platforms: ISharedPlatform;
            bill_external_id: string;
            uids: string[];
        }

        interface INotification {
            date: string;
        }

        interface IInfluence {
            count_bills_shared: number; // if a user has shared a bill in any way
            count_all_bill_shares: number; // total number of ways in which a user has shared a bill
            // countInvitesSent: number;
            count_invites_redeemed: number;
            count_bills_voted_on: number;
            count_facebook_shares: number;
            count_twitter_shares: number;
            count_telegram_shares: number;
            count_whatsapp_shares: number;
            count_email_shares: number;
            total_sway: number;
            uids: string[]; // can have duplicates
        }

        type TBillStatus = "passed" | "failed" | "committee" | "vetoed";
        type TBillCategory =
            | "immigration"
            | "police"
            | "health"
            | "housing"
            | "infrastructure"
            | "politics"
            | "civil rights"
            | "education"
            | "economy"
            | "transportation";

        interface IVote extends IIDObject {
            house_roll_call_vote_number: number;
            senate_roll_call_vote_number: number;
        }

        interface IApiBill {
            id?: number;
            external_id: string;
            external_version: string;
            title: string;
            summary?: string;
            link: string;
            chamber: TBillChamber;
            // vote_date_time_utc: string;
            introduced_date_time_utc: string;
            withdrawn_date_time_utc: string;
            house_vote_date_time_utc: string;
            senate_vote_date_time_utc: string;
            category: TBillCategory;
            status: TBillStatus;
            active: boolean;
            audio_bucket_path?: string;
            audio_by_line?: string;
            legislator_id: number;
            sway_locale_id: number;
            scheduled_release_date_utc: string; // Date string
        }

        // Used by UI
        interface IBill extends IIDObject {
            external_id: string;
            external_version: string;
            title: string;
            summary?: string;
            link: string;
            chamber: TBillChamber;
            vote_date_time_utc: string;
            introduced_date_time_utc: string;
            withdrawn_date_time_utc: string;
            house_vote_date_time_utc: string;
            senate_vote_date_time_utc: string;
            category: TBillCategory;
            status: TBillStatus;
            active: boolean;
            audio_bucket_path?: string;
            audio_by_line?: string;
            legislator_id: number;
            sway_locale_id: number;
            scheduled_release_date_utc: string; // Date string
            vote?: IVote;
        }
        interface IOrganizationBase extends IIDObject {
            sway_locale_id: number;
            name: string;
            icon_path?: string;
        }
        interface IOrganization extends IOrganizationBase {
            positions: IOrganizationPosition[];
        }

        interface IOrganizationPosition extends IIDObject {
            bill_id: number;
            support: string;
            summary: string;
        }

        interface IFormField<T> {
            name: Path<T>;
            subLabel?: string;
            type: "text" | "email" | "tel" | "number" | "boolean" | "date";
            component: "text" | "select" | "textarea" | "generatedText" | "checkbox" | "date" | "separator" | "radios";
            label: string;
            isRequired: boolean;
            default?: string | null;
            possibleValues?: ISelectOption[];
            disabled?: boolean;
            generateFields?: string[];
            joiner?: string;
            multi?: true;
            createable?: true;
            autoComplete?: string;
            helperText?: string;
            rows?: number;
            disableOn?: (values: any) => boolean;
            // colClass?: number;
            containerClassName?: string;
        }

        namespace scoring {
            interface ISupportable {
                for: number;
                against: number;
            }
            interface IBillScoreDistrctSupport extends ISupportable {
                district: IDistrict;
            }

            interface IBillScoreSupport extends ISupportable {
                bill_id: number;
                districts: IBillScoreDistrct[];
            }

            interface IAgreeable {
                count_agreed: number;
                count_disagreed: number;
                count_no_legislator_vote: number;
                count_legislator_abstained: number;
            }

            interface ILegislatorDistrictScore extends IAgreeable {
                legislator_id: number;
            }

            interface IUserLegislatorScore extends IAgreeable {
                user_legislator_id: number;
                legislator_id: number;
                sway_locale_id: number;
                legislator_district_score: ILegislatorDistrictScore;
            }
        }

        namespace files {
            interface IFileUpload {
                url: string; // the pre-signed url used to make a PUT request
                bucket_file_path: string; // the path to which a file should be uploaded
            }

            interface IXHRFileUploadRequestOptions {
                onProgress?: (s3ObjectPath: string, fileName: string, progress: number) => void;
                onDone?: (fileUpload: IFileUpload, progress: number) => void;
                onError?: (error: Error, s3ObjectPath?: string) => void;
                max?: number;
                extra?: Record<string, string | number | null>;
                retryCount?: number;
            }
        }

        namespace notifications {
            interface IPushNotificationSubscription extends IIDObject {
                endpoint: string;
                p256dh: string;
                auth: string;
                subscribed: boolean;
            }
        }

        namespace api {
            interface IApiKey extends IIDObject {
                token?: string;
                token_digest: string;
                bearer_type: string;
                bearer_id: number;
                created_at: string;
                name?: string;
                last_used_on_utc?: string;
            }
        }
    }
}
