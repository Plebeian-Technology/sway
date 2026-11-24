// @lat: [[web-profile-page#Web profile page]]
import { useUser } from "app/frontend/hooks/users/useUser";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { formatPhone } from "app/frontend/sway_utils/phone";
import { Link } from "@inertiajs/react";
import { Bell, ChevronRight, KeyRound, KeySquare, UserRound, Users } from "lucide-react";

interface IAccountLink {
    href: string;
    label: string;
    Icon: React.ComponentType<{ className?: string }>;
}

const ACCOUNT_LINKS: IAccountLink[] = [
    { href: ROUTES.users.organization_memberships, label: PARITY_COPY.profile.rows.memberships, Icon: Users },
    { href: ROUTES.notifications, label: PARITY_COPY.profile.rows.notificationPrefs, Icon: Bell },
    { href: ROUTES.users.passkeys, label: PARITY_COPY.profile.rows.passkeyManagement, Icon: KeyRound },
];

const API_KEYS_LINK: IAccountLink = { href: ROUTES.apiKeys, label: "API Keys", Icon: KeySquare };

interface IProps {
    can_manage_api_keys: boolean;
}

const Profile: React.FC<IProps> = ({ can_manage_api_keys }) => {
    const user = useUser();
    const accountLinks = can_manage_api_keys ? [...ACCOUNT_LINKS, API_KEYS_LINK] : ACCOUNT_LINKS;

    return (
        <div className="mx-auto w-full max-w-2xl space-y-6 px-4 py-6">
            <h1 className="text-2xl font-semibold tracking-tight text-foreground">{PARITY_COPY.profile.title}</h1>

            <div
                className="flex items-center gap-3 rounded-xl border-neo border-border-strong bg-card shadow-neo px-4 py-3"
                data-testid="profile-identity"
            >
                <div className="flex size-12 items-center justify-center rounded-full bg-accent text-accent-foreground">
                    <UserRound className="size-6" aria-hidden="true" />
                </div>
                <div>
                    {user?.full_name && <div className="text-lg font-semibold text-foreground">{user.full_name}</div>}
                    {user?.phone && (
                        <div className="text-sm text-muted-foreground tabular-nums">{formatPhone(user.phone)}</div>
                    )}
                </div>
            </div>

            <ul
                data-testid="profile-account-links"
                className="overflow-hidden rounded-xl border-neo border-border-strong bg-card shadow-neo"
            >
                {accountLinks.map(({ href, label, Icon }) => (
                    <li key={href} className="border-b border-border last:border-b-0">
                        <Link
                            href={href}
                            className="flex min-h-13 items-center gap-3 px-4 py-2 font-semibold text-foreground hover:bg-accent hover:text-accent-foreground"
                        >
                            <Icon className="size-5" aria-hidden="true" />
                            <span className="flex-1">{label}</span>
                            <ChevronRight className="size-4" aria-hidden="true" />
                        </Link>
                    </li>
                ))}
            </ul>
        </div>
    );
};

export default Profile;
