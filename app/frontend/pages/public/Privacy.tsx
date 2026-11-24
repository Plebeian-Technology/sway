import { Head, Link } from "@inertiajs/react";

// @lat: [[public-marketing-and-meta-pages#Why /sms, /privacy and /terms are Inertia pages under a second, minimal entrypoint]]
const Privacy: React.FC = () => {
    return (
        <>
            <Head title="Privacy Policy - Sway" />
            <section className="mx-auto w-full max-w-2xl px-6 py-16">
                <h1 className="text-2xl font-black text-foreground">Privacy Policy</h1>

                <p className="mt-6 text-sm text-muted-foreground">
                    Sway is a civic engagement platform where you vote on the same legislation as your elected
                    representatives. This page explains what information we collect, why we collect it, how long we keep
                    it, and who it is shared with.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">What we collect</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    We collect the information you give us. We also count how far visitors get through sign-up. For that
                    we give each browser a random visitor token and record the sign-up step it reaches and the link that
                    referred it. These records hold no phone numbers or street addresses. We store them ourselves and
                    send them to no analytics service. When you create an account, we link them to it. We do not show
                    ads.
                </p>
                <ul className="mt-3 list-disc space-y-2 pl-6 text-sm text-muted-foreground">
                    <li>
                        <span className="font-semibold text-foreground">Phone number</span> — used to create and secure
                        your account, to verify you are a real person, and to send the SMS alerts you opt into (see{" "}
                        <Link href="/sms" className="underline">
                            /sms
                        </Link>
                        ).
                    </li>
                    <li>
                        <span className="font-semibold text-foreground">Address</span> — used only to determine your
                        legislative district and assign your elected representatives, so we can compare your votes
                        against theirs.
                    </li>
                    <li>
                        <span className="font-semibold text-foreground">Votes you cast on legislation</span> — stored so
                        you can track your own voting history and see how it compares with your representatives.
                    </li>
                </ul>

                <h2 className="mt-8 text-lg font-black text-foreground">Why we collect it</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    We collect only what Sway needs to run: to confirm your identity, to route you to the correct
                    district and representatives, and to record your positions on legislation. We do not collect
                    information for advertising or profiling nor do we share any information for those purposes.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">How long we keep it</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    We keep account and voting data for as long as your account is active, so your voting history stays
                    available to you. Can I delete my Sway account? Yes. You can remove all your data at any point. You
                    can do this by deleting your account from your Profile page on the web or in the Sway mobile app.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">Who we share it with</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    Does Sway sell my data? No. Will Sway ever sell my data? Never. We may one day offer a way for you
                    to sell your own data, and only with your explicit permission. If we do, we would likely take a
                    small percentage of any proceeds. We share data only in these limited cases:
                </p>
                <ul className="mt-3 list-disc space-y-2 pl-6 text-sm text-muted-foreground">
                    <li>
                        A few services help run Sway. Twilio sends the text message that verifies your phone number and
                        the SMS alerts you opt into. Firebase delivers push notifications. Sentry receives error reports
                        so we can fix bugs, and we configure it to leave out personal data. Google Cloud Storage holds
                        our backups.
                    </li>
                    <li>When required by law, such as in response to a valid legal request.</li>
                    <li>
                        Aggregated or de-identified data (for example, district-level vote totals) that cannot
                        reasonably be traced back to you.
                    </li>
                </ul>

                <p className="mt-4 rounded-md border-neo border-border bg-muted p-4 text-sm font-semibold text-foreground">
                    Mobile phone numbers and SMS opt-in data are never sold, rented, or shared with third parties for
                    marketing purposes.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">Your choices</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    You can opt out of SMS at any time by replying STOP, or by unchecking the SMS consent box in your
                    account settings at{" "}
                    <a
                        href="https://app.sway.vote/notifications"
                        className="underline"
                        target="_blank"
                        rel="noopener noreferrer"
                    >
                        https://app.sway.vote/notifications
                    </a>
                    . You can remove all your data at any point. You can do that by deleting your account in the Sway
                    mobile app, or by contacting us.
                </p>

                <p className="mt-8 text-sm text-muted-foreground">
                    See also our{" "}
                    <Link href="/terms" className="underline">
                        terms of service
                    </Link>{" "}
                    and the{" "}
                    <Link href="/sms" className="underline">
                        SMS program disclosure
                    </Link>
                    .
                </p>
            </section>
        </>
    );
};

export default Privacy;
