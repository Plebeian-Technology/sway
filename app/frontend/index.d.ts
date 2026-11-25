declare module "@rails/activestorage" {
    export function start(): void;

    export interface IDirectUploadDelegate {
        directUploadWillStoreFileWithXHR?(xhr: XMLHttpRequest): void;
    }

    export interface IDirectUploadBlob {
        signed_id: string;
    }

    export class DirectUpload {
        constructor(file: File, url: string, delegate?: IDirectUploadDelegate);

        create(callback: (error: string | Error | null, blob: IDirectUploadBlob | null) => void): void;
    }
}

declare module "sway" {
    type EitherOnly<T, U> = {
        [P in keyof T]: T[P];
    } & {
        [P in keyof U]?: never;
    };
    type Either<T, U> = EitherOnly<T, U> | EitherOnly<U, T>;

    type KeyOf<T> = Extract<keyof T, string>;
    type KeyOfOmit<T, K> = Omit<Extract<keyof T, string>, K>;

    type ValueOf<T> = T[keyof T];

    interface IIDObject {
        id: number;
    }

    type Path<T> = T extends object
        ? {
              [K in keyof T]: `${Exclude<K, symbol>}${"" | `.${Paths<T[K]>}`}`;
          }[keyof T]
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

        // @lat: [[inertia-page-props#The page-props interface covers shared flash and errors]]
        interface IPageProps extends Record<string, unknown> {
            user: sway.IUser;
            sway_locale: sway.ISwayLocale;
            sway_locales: sway.ISwayLocale[];
            // @lat: [[identity-and-access#User JSON exposes only selected fields#Locale props are never cached once per browser]]
            sway_locale_options: ISelectOption[];
            // @lat: [[identity-and-access#User JSON exposes only selected fields#Locale props are never cached once per browser]]
            admin_sway_locale_options?: ISelectOption[] | null;
            legislator_photo_urls?: string[];
            flash?: sway.IFlash;
            errors?: Record<string, unknown>;
            // @lat: [[system-shape#Deployment#The logo tooltip includes the running build]]
            release?: sway.IRelease;
            reassignment_notifications?: sway.IRepresentativeReassignment[];
            representative_reassignments?: sway.IRepresentativeReassignment[];
            pending_vote?: { bill_id: number; support: sway.TUserSupport } | null;
            public_testimony_counts?: sway.IPublicTestimonyCounts | null;
            public_testimony_letters?: sway.IPublicTestimonyLetter[] | null;
        }

        type TReassignmentType = "district_changed" | "successor_seeded" | "vacant_seat" | "vacancy_filled";

        interface IRepresentativeReassignment {
            id: number;
            reassignment_type: TReassignmentType;
            district_id?: number | null;
            previous_district_id?: number | null;
            legislator_id?: number | null;
            previous_legislator_id?: number | null;
            district?: sway.IDistrict | null;
            previous_district?: sway.IDistrict | null;
            legislator?: sway.ILegislator | null;
            previous_legislator?: sway.ILegislator | null;
            created_at: string;
            dismissed_at?: string | null;
        }

        interface IFlash {
            id?: string;
            notice?: string;
            alert?: string;
            bill_share_path?: string;
            // @lat: [[api-keys-page-spec-contract#Key display flow]]
            new_api_key_token?: string;
        }

        // @lat: [[system-shape#Deployment#The version page has three answers, not two]]
        interface IRelease {
            version: number | null;
            sha: string | null;
            short_sha: string | null;
            previous_sha: string | null;
            previous_short_sha: string | null;
            deployed_at: string | null;
            // @lat: [[system-shape#Deployment#The version page has three answers, not two]]
            uncommitted_digest: string | null;
            // @lat: [[system-shape#System shape#Deployment#The version page has three answers, not two]]
            built_from_committed_tree: boolean | null;
        }

        interface IOssDependency {
            name: string;
            version: string;
            license: string;
            homepage: string | null;
        }

        type TAlertLevel = "info" | "success" | "warning" | "error";

        type TParty = "D" | "R" | "I" | "X";

        // @lat: [[system-shape#System shape#One process, two languages#Why a payload goes through a resource rather than the record]]
        interface IAddress extends IIDObject {
            street: string;
            street2?: string;
            city: string;
            region_code: string;
            country: string;
            postal_code: string;
            full_address: string;
        }

        interface IDistrict extends IIDObject {
            name: string;
            number: number;
            region_code: string;
        }

        interface ISwayLocale extends IIDObject {
            name: string;
            city: string;
            region_code: string;
            region_name: string;
            country: string;
            icon_url: string;
            time_zone: string;
            current_session_start_date: string;
            // @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
            default_bill_chamber: TBillChamber | null;
            // @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
            bill_chambers: TBillChamber[] | null;
            generic_portal_urls?: string[];
            nominatim_viewbox?: string | null;
            nominatim_bounded?: boolean | null;
            nominatim_country_codes?: string | null;
        }

        interface IUser extends IIDObject {
            id: number;
            full_name?: string;
            email: string | null;
            phone: string;
            invite_url: string | null;
            // @lat: [[identity-and-access#Registration is asynchronous by necessity]]
            is_registration_complete: boolean;
            is_registered_to_vote: boolean;
            is_email_verified: boolean;
            is_phone_verified: boolean;
            is_sway_confirmed: boolean;
            address: IAddress;
            locales: ISwayLocale[];
            is_admin?: boolean;
            is_sway_admin?: boolean;
            beszel_url?: string;
            memberships: IOrganizationMembership[];
            sms_notifications_enabled: boolean;
            registration_status?: string;
        }

        // @lat: [[system-shape#System shape#One process, two languages#Why a payload goes through a resource rather than the record]]
        interface IApiUserVote {
            id: number;
            bill_id: number;
            support: sway.TUserSupport;
        }

        // @lat: [[outbound-email#Outbound email#The preview is built from the object the mailer renders]]
        interface IEmailPreview {
            subject: string;
            intro: string;
            body: string;
            conclusion: string;
            bill_link: string | null;
        }

        type TUserLegislatorEmailStatus = "pending" | "sending" | "sent" | "failed";

        interface IUserLegislatorEmail {
            id: number;
            bill_id: number;
            status: TUserLegislatorEmailStatus;
            legislator_id: number;
            legislator_full_name: string;
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
            legislator: ILegislator;
            bill: IBill;
            support: TLegislatorSupport;
        }

        interface ILegislatorBillSupport {
            [external_legislator_id: string]: sway.TLegislatorSupport;
        }

        interface ILegislator extends IIDObject {
            sway_locale_id: number;
            party: TParty;
            title: string;
            first_name: string;
            last_name: string;
            full_name: string;
            external_id: string;
            active: boolean;
            link: string;
            email: string;
            // @lat: [[legislator-resource-design#Why term toggle and history copy coordinates with display_term]]
            district: IDistrict | null;
            phone: string;
            fax?: string;
            address?: IAddress;
            photo_url?: string;
            twitter?: string;
            // @lat: [[legislator-resource-design#Why term toggle and history copy coordinates with display_term]]
            term_start_year?: number | null;
            term_end_year?: number | null;
            // @lat: [[current-legislator-term#Which term a legislator is serving now#A term carries the day it really began]]
            began_on?: string | null;
            ended_on?: string | null;
            user_legislator_score?: scoring.IUserLegislatorScore | null;
            // @lat: [[legislators-controller-design#LegislatorsController design#Score props retain their established shape]]
            lifetime_score?: scoring.IUserLegislatorScore | null;
            // @lat: [[legislator-history-serialization#Read-only historical term agreement serialization]]
            terms?: ILegislatorTermEntry[];
        }

        interface IHistoricalScoreExplanation {
            title: string;
            body: string;
            delta: number | null;
            score_type: string;
        }

        interface ILegislatorTermEntry {
            id: number;
            session_label: string;
            term_start_year: number;
            term_end_year: number;
            began_on: string | null;
            ended_on: string | null;
            district_name: string | null;
            is_executive: boolean;
            active: boolean;
            district_score: scoring.IGroupAgreeable | null;
            locale_score: scoring.IGroupAgreeable | null;
            user_score: scoring.IAgreeable | null;
            correction_explanation: IHistoricalScoreExplanation | null;
        }

        // @lat: [[voter-privacy-threshold#Bill totals are sent as rounded percentages]]
        interface IBaseScore {
            for: number | null;
            against: number | null;
            comparison_suppressed: boolean;
            voters_needed: number;
        }

        // @lat: [[voter-privacy-threshold#Districts are sent as percentages only]]
        interface IBillScoreDistrct {
            district: IDistrict;
            comparison_suppressed: boolean;
            for_percent: number | null;
            against_percent: number | null;
            at_large: boolean;
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

        interface IAggregatedBillLocaleScores {
            count_all_users_in_locale: number;
            count_all_users_in_district: number;
            external_legislator_id: string;
            bill_scores: IBillLocaleScore[] | undefined;
        }

        type TBillChamber = "house" | "senate" | "council" | "both";

        interface IInfluence {
            count_bills_shared: number;
            count_all_bill_shares: number;
            count_invites_redeemed: number;
            count_bills_voted_on: number;
            count_facebook_shares: number;
            count_twitter_shares: number;
            count_telegram_shares: number;
            count_whatsapp_shares: number;
            count_email_shares: number;
            total_sway: number;
            uids: string[];
        }

        type TBillStatus = "passed" | "failed" | "committee" | "vetoed";
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
            // @lat: [[ai-unreviewed-notice-component-design#AiUnreviewedNotice component design#The server sends a derived boolean, not the source text]]
            summary_ai_unreviewed?: boolean;
            link: string;
            chamber: TBillChamber;
            introduced_date_time_utc: string;
            withdrawn_date_time_utc: string;
            house_vote_date_time_utc: string;
            senate_vote_date_time_utc: string;
            category: string;
            categories?: string[];
            status: TBillStatus;
            active: boolean;
            audio_bucket_path?: string;
            audio_by_line?: string;
            legislator_id: number;
            sway_locale_id: number;
            scheduled_release_date_utc: string;
        }

        // @lat: [[news-article-evidence#Changes after publication]]
        interface INewsArticle extends IIDObject {
            title: string;
            url: string;
            outlet_name: string;
            author_name?: string | null;
            published_at: string | null;
            article_kind: "reporting" | "op_ed" | "editorial" | "unknown";
            match_kind: "direct" | "context";
        }

        // @lat: [[news-article-evidence#Changes after publication]]
        interface INewsArticleTestimony extends IIDObject {
            author_name?: string | null;
            outlet_name: string;
            url: string;
            stance: "support" | "oppose";
            argument: string;
        }

        interface IBill extends IIDObject {
            external_id: string;
            external_version: string;
            title: string;
            summary?: string;
            // @lat: [[ai-unreviewed-notice-component-design#AiUnreviewedNotice component design#The server sends a derived boolean, not the source text]]
            summary_ai_unreviewed?: boolean;
            link: string | null;
            chamber: TBillChamber;
            vote_date_time_utc: string;
            introduced_date_time_utc: string;
            withdrawn_date_time_utc: string;
            house_vote_date_time_utc: string;
            senate_vote_date_time_utc: string;
            category: string;
            categories?: string[];
            status: TBillStatus;
            active: boolean;
            audio_bucket_path?: string;
            audio_by_line?: string;
            legislator_id: number;
            sway_locale_id: number;
            scheduled_release_date_utc: string;
            vote?: IVote;
            bill_score?: scoring.IBillScore;
            user_vote?: IApiUserVote;
            related_articles?: INewsArticle[];
            news_testimonies?: INewsArticleTestimony[];
        }

        interface IPublicTestimonyCounts {
            total: number;
            support: number;
            oppose: number;
            neutral: number;
        }

        interface IPublicTestimonyLetter {
            position: number;
            label: string;
            stance: "support" | "oppose" | "neutral";
            body_text: string;
        }

        // @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
        interface IBillPickerOption extends IIDObject {
            external_id: string;
            title: string;
            scheduled_release_date_utc: string | null;
            status: string | null;
            chamber: string;
            category: string;
            introduced_date_time_utc: string | null;
            latest_action_date_time_utc: string | null;
            sponsor_name: string;
            legislator_vote_count: number;
            organization_position_count: number;
            // @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
            interesting_badges: Array<"controversial" | "close" | "live">;
            interesting_score_normalized: number | null;
        }
        interface IOrganizationBase extends IIDObject {
            sway_locale_id: number;
            name: string;
            icon_url?: string;
        }
        interface IOrganization extends IOrganizationBase {
            positions: IOrganizationPosition[];
        }

        interface IOrganizationPosition extends IIDObject {
            bill_id: number;
            support: string;
            summary: string | null;
            // @lat: [[ai-unreviewed-notice-component-design#AiUnreviewedNotice component design#The server sends a derived boolean, not the source text]]
            summary_ai_unreviewed?: boolean;
            origin: "Org-posted" | "Sway-compiled";
            origin_url?: string | null;
        }

        // @lat: [[organization-position-removal#Bill reader positions include their organization]]
        interface IBillOrganizationPosition extends IOrganizationPosition {
            organization: IOrganizationBase;
        }

        interface IOrganizationMembership extends IIDObject {
            user_id: number;
            organization: IOrganizationBase;
            role: "admin" | "standard";
            positions_count?: number;
            pending_changes_count?: number;
        }

        // @lat: [[public-organizations-endpoint#The public organizations endpoint]]
        interface IPublicOrganization extends IIDObject {
            name: string;
            icon_url?: string | null;
            sway_locale_id: number;
            sway_locale_slug?: string | null;
            created_at?: string;
        }

        // @lat: [[organization-follows-controller#The follow preference payload matches the saved controls]]
        interface IOrgFollowPrefs {
            follow_id: number;
            notify_on_new_position: boolean;
            notify_on_support_change: boolean;
            notify_on_summary_change: boolean;
            notification_cadence: "every_change" | "daily" | "weekly";
            muted: boolean;
        }

        // @lat: [[org-notification-cascade-and-defaults#User and follow cadence enums keep the same integer mapping]]
        interface IOrgDefaultPrefs {
            notify_on_new_position: boolean;
            notify_on_support_change: boolean;
            notify_on_summary_change: boolean;
            notification_cadence: "every_change" | "daily" | "weekly";
        }

        // @lat: [[public-organizations-endpoint#What a signed-out reader is never sent]]
        interface IOrganizationFollowPageProps {
            user_follows?: Record<number, number>;
            user_follow_prefs?: Record<number, IOrgFollowPrefs>;
            current_user_org_defaults?: IOrgDefaultPrefs;
            current_user_follow_id?: number | null;
            is_member_of_org_ids?: number[];
        }

        interface IPublicOrganizationPosition extends IIDObject {
            organization_id: number;
            bill_id: number;
            support: string;
            summary?: string | null;
            // @lat: [[ai-unreviewed-notice-component-design#AiUnreviewedNotice component design#The server sends a derived boolean, not the source text]]
            summary_ai_unreviewed?: boolean;
            active: boolean;
            created_at?: string;
            origin: "Org-posted" | "Sway-compiled";
            origin_url?: string | null;
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

            // @lat: [[voter-privacy-threshold#Legislator scores are sent as percentages]]
            interface IGroupAgreeable {
                comparison_suppressed: boolean;
                agreed_percent: number | null;
                disagreed_percent: number | null;
                no_legislator_vote_percent: number | null;
                legislator_abstained_percent: number | null;
                // Agreed share of agreed plus disagreed pairs.
                voter_agreement_percent: number | null;
            }

            interface ILegislatorDistrictScore extends IGroupAgreeable {
                legislator_id: number;
            }

            interface IUserLegislatorScore extends IAgreeable {
                user_legislator_id: number;
                legislator_id: number;
                sway_locale_id: number;
                legislator_district_score: ILegislatorDistrictScore;
                legislator_locale_score?: ILegislatorDistrictScore | null;
            }
        }

        // @lat: [[legislator-history-serialization#Legislator history serialization]]
        namespace legislatorHistory {
            interface ITerm {
                term_start_year: number;
                term_end_year: number;
                began_on: string | null;
                ended_on: string | null;
                title: string;
                district: IDistrict;
            }

            type TEndedReason = "term_ended" | "district_changed" | "link_inactive";

            interface IEntry {
                legislator: ILegislator;
                term: ITerm;
                score: scoring.IAgreeable;
                ended_reason: TEndedReason;
            }

            interface ISession {
                session_label: string;
                entries: IEntry[];
            }

            interface IHistory {
                sessions: ISession[];
            }
        }

        namespace notifications {
            // @lat: [[system-shape#System shape#One process, two languages#Why a payload goes through a resource rather than the record]]
            interface IPushNotificationSubscription extends IIDObject {
                endpoint: string;
                subscribed: boolean;
                created_at: string;
            }
        }

        namespace api {
            // @lat: [[api-key-page-payload#Listing a key never returns its digest or bearer identity]]
            interface IApiKey extends IIDObject {
                created_at: string;
                name?: string;
                last_used_on_utc?: string;
            }
        }
    }
}
