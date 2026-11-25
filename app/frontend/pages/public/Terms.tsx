import { Head, Link } from "@inertiajs/react";

// @lat: [[public-marketing-and-meta-pages#Why MarketingController sms, privacy and terms exist]]
const Terms: React.FC = () => {
    return (
        <>
            <Head title="Terms of Service - Sway" />
            <section className="mx-auto w-full max-w-2xl px-6 py-16">
                <h1 className="text-2xl font-black text-foreground">Terms of Service</h1>

                <p className="mt-6 text-sm text-muted-foreground">
                    These terms cover your use of Sway, a civic engagement platform where you vote on the same
                    legislation as your elected representatives.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">Acceptable use</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    Use Sway to inform yourself about legislation, cast your own votes, and track organizations and
                    representatives you care about. Do not use Sway to impersonate someone else, submit votes on another
                    person&apos;s behalf, or interfere with the platform&apos;s operation.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">Sway is free</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    Sway is free to use. We do not charge for an account, for voting, or for tracking organizations and
                    representatives.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">Accounts</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    Creating an account requires a mobile phone number that you verify by SMS. One phone number
                    identifies one account. You are responsible for keeping access to your phone number and account
                    secure.
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">Messaging terms</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    If you opt in to text alerts, Sway sends about 1-3 messages per week: new Bill of the Month alerts,
                    voting reminders, and notices when Sway records a position on a bill from an organization you track.
                    Msg&amp;data rates may apply. Reply STOP to cancel, or HELP for help. Opting into SMS is optional
                    and never required to use Sway. Full detail:{" "}
                    <Link href="/sms" className="underline">
                        /sms
                    </Link>
                    .
                </p>

                <h2 className="mt-8 text-lg font-black text-foreground">Changes</h2>
                <p className="mt-3 text-sm text-muted-foreground">
                    We may update these terms as Sway changes. Continued use of Sway after an update means you accept
                    the revised terms.
                </p>

                <p className="mt-8 text-sm text-muted-foreground">
                    See also our{" "}
                    <Link href="/privacy" className="underline">
                        privacy policy
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

export default Terms;
