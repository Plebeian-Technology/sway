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
                    available to you. If you delete your account, we remove your personal information within a
                    reasonable period, except where we are required to retain records by law.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">Who we share it with</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    We do not sell your personal information. We share data only in these limited cases:
                </p>
                <ul className="mt-3 list-disc space-y-2 pl-6 text-sm text-muted-foreground">
                    <li>
                        Service providers who help us operate Sway (for example, hosting and SMS delivery), bound to use
                        your data only to provide that service. For example, we must share your phone number with our
                        SMS provider, Twilio (as of this writing) in order to send you SMS messages.
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
                    . You can request deletion of your account and data by contacting us or through the application.
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
