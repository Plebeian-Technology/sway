import { CircleHelp } from "lucide-react";
import type React from "react";

import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
    DialogTrigger,
} from "app/frontend/components/ui/dialog";

const WALKTHROUGH_MAILTO = "mailto:info@sway.vote?subject=Privacy%20walkthrough%20request";

// @lat: [[support-bubble#Support bubble placement]]
const SupportBubble: React.FC = () => {
    return (
        <Dialog>
            <DialogTrigger asChild>
                <Button
                    type="button"
                    variant="secondary"
                    size="icon"
                    aria-label="Support"
                    className="fixed right-4 bottom-[max(1rem,env(safe-area-inset-bottom))] z-40 size-11 min-h-11 min-w-11 rounded-full"
                >
                    <CircleHelp className="size-5" aria-hidden="true" />
                </Button>
            </DialogTrigger>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Request a privacy walkthrough</DialogTitle>
                    <DialogDescription>
                        Sway runs privacy walkthroughs over video chat, where we show you the app, the database, and,
                        with your permission, your own account data.
                    </DialogDescription>
                </DialogHeader>
                <DialogFooter>
                    <Button asChild className="min-h-11">
                        <a href={WALKTHROUGH_MAILTO}>Email us to schedule</a>
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
};

export default SupportBubble;
