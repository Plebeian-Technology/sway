import { Head, Link } from "@inertiajs/react";

import SmsNotificationsPanelView from "app/frontend/components/notifications/SmsNotificationsPanelView";
import { SMS_CONSENT_LABEL } from "app/frontend/sway_constants/smsConsent";

// @lat: [[public-disclosure-pages#Why the carrier reviewer needs a page with no account]]

interface IProps {
    sms_phone: string | null;
}

const Sms: React.FC<IProps> = ({ sms_phone }) => {
    return (
        <>
            <Head title="SMS Program - Sway legislation alerts" />
            <section className="mx-auto w-full max-w-2xl px-6 py-16">
                <h1 className="text-2xl font-black text-foreground">Sway legislation alerts (SMS)</h1>
                <p className="mt-4 text-sm text-muted-foreground">
                    &quot;Sway legislation alerts&quot; is the text messaging program run by Sway, a free civic
                    engagement platform where you vote on the same legislation as your elected representatives.
                </p>

                {sms_phone && (
                    <p className="mt-6 rounded-lg border border-border px-4 py-3 text-base text-foreground">
                        Messages come from <span className="font-black tabular-nums lining-nums">{sms_phone}</span>.
                    </p>
                )}

                <h2 className="mt-8 text-lg font-black text-foreground">What messages we send</h2>
                <ul className="mt-3 list-disc space-y-3 pl-6 text-sm text-muted-foreground">
                    <li>
                        New Bill of the Month alerts, for example:
                        <blockquote className="mt-1 border-l-neo border-border pl-3 italic">
                            &quot;New Bill of the Month in Baltimore: [bill title]. Check it out on Sway!&quot;
                        </blockquote>
                    </li>
                    <li>
                        Voting reminders, for example:
                        <blockquote className="mt-1 border-l-neo border-border pl-3 italic">
                            &quot;Sway: You haven&apos;t voted on the featured bill in Baltimore: [bill title]. Vote
                            now!&quot;
                        </blockquote>
                    </li>
                    <li>
                        Organization position notices, sent when an advocacy organization you follow takes a position on
                        a bill.
                    </li>
                </ul>

                <h2 className="mt-8 text-lg font-black text-foreground">Frequency &amp; cost</h2>
                <p className="mt-3 text-sm text-muted-foreground">1-3 messages per week.</p>
                <p className="mt-1 text-sm text-muted-foreground">Msg&amp;data rates may apply.</p>
                <p className="mt-1 text-sm text-muted-foreground">Reply STOP to cancel. Reply HELP for help.</p>

                <h2 className="mt-8 text-lg font-black text-foreground">The consent screen</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    Below is a live preview of the SMS panel signed-in users see at{" "}
                    <a
                        href="https://app.sway.vote/notifications"
                        className="underline"
                        target="_blank"
                        rel="noopener noreferrer"
                    >
                        https://app.sway.vote/notifications
                    </a>
                    . It is drawn by the same component, with the same text, as the real page, so the two cannot drift
                    apart.
                </p>

                <figure className="mt-4" aria-labelledby="sms-consent-preview-caption">
                    <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                        Preview, not interactive
                    </p>
                    <SmsNotificationsPanelView enabled={false} sms_phone={sms_phone} preview />
                    <figcaption id="sms-consent-preview-caption" className="mt-2 text-xs text-muted-foreground">
                        Preview of the consent panel as a new account sees it, with its controls disabled here. The
                        checkbox is unchecked by default and never pre-selected. SMS is off for every new account until
                        a user opts in.
                    </figcaption>
                </figure>

                <h2 className="mt-8 text-lg font-black text-foreground">How a user opts in</h2>
                <ol className="mt-3 list-decimal space-y-2 pl-6 text-sm text-muted-foreground">
                    <li>
                        Create a Sway account at{" "}
                        <a href="https://sway.vote" className="underline" target="_blank" rel="noopener noreferrer">
                            https://sway.vote
                        </a>{" "}
                        and verify your mobile number.
                    </li>
                    <li>
                        Open Notifications in the account menu, at{" "}
                        <a
                            href="https://app.sway.vote/notifications"
                            className="underline"
                            target="_blank"
                            rel="noopener noreferrer"
                        >
                            https://app.sway.vote/notifications
                        </a>
                        .
                    </li>
                    <li>Check the box labeled &quot;{SMS_CONSENT_LABEL}&quot; and click Save preferences.</li>
                </ol>

                <p className="mt-8 text-sm text-muted-foreground">
                    See our{" "}
                    <Link href="/privacy" className="underline">
                        privacy policy
                    </Link>{" "}
                    and{" "}
                    <Link href="/terms" className="underline">
                        terms of service
                    </Link>
                    .
                </p>
            </section>
        </>
    );
};

export default Sms;
