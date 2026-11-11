// @lat: [[organization-follow-control-state-machine#Why the preferences-picker's open/closed state lives above the follow/unfollow branch]]

import { useState } from "react";
import { useForm } from "@inertiajs/react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";
import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import OrgPreferencePickerModal from "app/frontend/components/organizations/OrgPreferencePickerModal";
import { sway } from "sway";

interface IProps {
    organization: sway.IPublicOrganization;
    followId?: number | null;
    // @lat: [[organization-follow-control-state-machine#IProps fields]]
    isMember: boolean;
    isMuted?: boolean;
    isSignedIn: boolean;
    masterEnabled: boolean;
    // @lat: [[organization-follow-control-state-machine#IProps fields]]
    followPrefs?: sway.IOrgFollowPrefs | null;
    // @lat: [[organization-follow-control-state-machine#IProps fields]]
    orgDefaults?: sway.IOrgDefaultPrefs | null;
}

interface FollowFormProps {
    organization: sway.IPublicOrganization;
    masterEnabled: boolean;
    // @lat: [[organization-follow-control-state-machine#Why the preferences-picker's open/closed state lives above the follow/unfollow branch]]
    onFollowSuccess: () => void;
}

const FollowForm: React.FC<FollowFormProps> = ({ organization, masterEnabled: _masterEnabled, onFollowSuccess }) => {
    const { post, processing } = useForm({
        organization_id: organization.id,
    });

    const follow = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        post(ROUTES.organizationFollows, {
            preserveScroll: true,
            // @lat: [[organization-follow-control-state-machine#Why the preferences-picker's open/closed state lives above the follow/unfollow branch]]
            onSuccess: onFollowSuccess,
        });
    };

    return (
        <form onSubmit={follow}>
            <Button type="submit" variant="default" disabled={processing} data-testid={`follow-btn-${organization.id}`}>
                {PARITY_COPY.orgs.follow}
            </Button>
        </form>
    );
};

interface UnfollowControlProps {
    organization: sway.IPublicOrganization;
    followId: number;
    masterEnabled: boolean;
    onPreferencesClick: () => void;
}

const UnfollowControl: React.FC<UnfollowControlProps> = ({
    organization,
    followId,
    masterEnabled: _masterEnabled,
    onPreferencesClick,
}) => {
    const { delete: destroy, processing } = useForm({});

    const unfollow = (e: React.SubmitEvent<HTMLFormElement>) => {
        e.preventDefault();
        destroy(ROUTES.organizationFollow(followId), {
            preserveScroll: true,
        });
    };

    return (
        <div className="flex flex-wrap items-center gap-2">
            <form onSubmit={unfollow}>
                <Button
                    type="submit"
                    variant="outline"
                    disabled={processing}
                    aria-label={`Unfollow ${organization.name}`}
                    data-testid={`following-btn-${organization.id}`}
                >
                    {PARITY_COPY.orgs.unfollow}
                </Button>
            </form>
            <Button variant="outline" onClick={onPreferencesClick} data-testid={`preferences-btn-${organization.id}`}>
                Preferences
            </Button>
        </div>
    );
};

interface MemberControlProps {
    organization: sway.IPublicOrganization;
    isMuted: boolean;
    onPreferencesClick: () => void;
}

const MemberControl: React.FC<MemberControlProps> = ({ organization, isMuted, onPreferencesClick }) => (
    <div className="flex flex-wrap items-center gap-2">
        <Badge variant="stamp" tone="neutral" data-testid={`member-badge-${organization.id}`}>
            {isMuted ? "Muted · member" : "Following · member"}
        </Badge>
        <Button
            variant="outline"
            onClick={onPreferencesClick}
            data-testid={`member-preferences-btn-${organization.id}`}
        >
            Preferences
        </Button>
    </div>
);

const OrganizationFollowControl: React.FC<IProps> = ({
    organization,
    followId,
    isMember,
    isMuted = false,
    isSignedIn,
    masterEnabled,
    followPrefs,
    orgDefaults,
}) => {
    // @lat: [[organization-follow-control-state-machine#Why the preferences-picker's open/closed state lives above the follow/unfollow branch]]
    const [pickerOpen, setPickerOpen] = useState(false);
    const [pickerIsFirstFollow, setPickerIsFirstFollow] = useState(false);

    if (!isSignedIn) {
        return null;
    }

    // @lat: [[organization-follow-control-state-machine#Why the preferences-picker's open/closed state lives above the follow/unfollow branch]]
    const seedPrefs = followPrefs ?? orgDefaults;
    const initialNotifyOnNewPosition = seedPrefs?.notify_on_new_position;
    const initialNotifyOnSupportChange = seedPrefs?.notify_on_support_change;
    const initialNotifyOnSummaryChange = seedPrefs?.notify_on_summary_change;
    const initialCadence = seedPrefs?.notification_cadence;

    if (isMember) {
        // @lat: [[organization-follow-control-state-machine#Why the preferences-picker's open/closed state lives above the follow/unfollow branch]]
        const isCreateMode = !followId;
        const memberSeedPrefs = followPrefs ?? orgDefaults;
        return (
            <>
                <MemberControl
                    organization={organization}
                    isMuted={isMuted}
                    onPreferencesClick={() => setPickerOpen(true)}
                />
                {pickerOpen && (
                    <OrgPreferencePickerModal
                        organization={organization}
                        followId={followId ?? 0}
                        isFirstFollow={isCreateMode}
                        createMode={isCreateMode}
                        masterEnabled={masterEnabled}
                        open={pickerOpen}
                        onClose={() => setPickerOpen(false)}
                        initialNotifyOnNewPosition={memberSeedPrefs?.notify_on_new_position}
                        initialNotifyOnSupportChange={memberSeedPrefs?.notify_on_support_change}
                        initialNotifyOnSummaryChange={memberSeedPrefs?.notify_on_summary_change}
                        initialCadence={memberSeedPrefs?.notification_cadence}
                    />
                )}
            </>
        );
    }

    if (followId) {
        return (
            <>
                <UnfollowControl
                    organization={organization}
                    followId={followId}
                    masterEnabled={masterEnabled}
                    onPreferencesClick={() => {
                        setPickerIsFirstFollow(false);
                        setPickerOpen(true);
                    }}
                />
                {pickerOpen && (
                    <OrgPreferencePickerModal
                        organization={organization}
                        followId={followId}
                        isFirstFollow={pickerIsFirstFollow}
                        masterEnabled={masterEnabled}
                        open={pickerOpen}
                        onClose={() => {
                            setPickerOpen(false);
                            setPickerIsFirstFollow(false);
                        }}
                        initialNotifyOnNewPosition={initialNotifyOnNewPosition}
                        initialNotifyOnSupportChange={initialNotifyOnSupportChange}
                        initialNotifyOnSummaryChange={initialNotifyOnSummaryChange}
                        initialCadence={initialCadence}
                    />
                )}
            </>
        );
    }

    // @lat: [[organization-follow-control-state-machine#Why the preferences-picker's open/closed state lives above the follow/unfollow branch]]
    return (
        <FollowForm
            organization={organization}
            masterEnabled={masterEnabled}
            onFollowSuccess={() => {
                setPickerIsFirstFollow(true);
                setPickerOpen(true);
            }}
        />
    );
};

export default OrganizationFollowControl;
