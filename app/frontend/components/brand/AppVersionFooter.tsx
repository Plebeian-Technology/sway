import { Link, usePage } from "@inertiajs/react";
import { sway } from "sway";

import { cn } from "app/frontend/lib/utils";
import { releaseLabel } from "app/frontend/sway_utils/release";

// @lat: [[system-shape#Deployment#The logo tooltip includes the running build]]
interface IProps {
    className?: string;
}

const AppVersionFooter: React.FC<IProps> = ({ className }) => {
    const release = usePage<sway.IPageProps>().props.release;

    return (
        <footer
            className={cn(
                "mt-10 flex flex-wrap items-center justify-center gap-x-2 gap-y-1 border-t-neo border-border pt-4 text-xs text-muted-foreground",
                className,
            )}
        >
            <Link href="/version" className="font-semibold underline-offset-4 hover:underline">
                {releaseLabel(release)}
            </Link>
            {release?.short_sha ? <span className="font-mono">{release.short_sha}</span> : null}
            <span aria-hidden="true">·</span>
            <Link href="/licenses" className="underline-offset-4 hover:underline">
                Open-source licenses
            </Link>
        </footer>
    );
};

export default AppVersionFooter;
