import copy from "copy-to-clipboard";
import { useCallback, useMemo } from "react";
import { Button } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";
import { useUser } from "../../../hooks/users/useUser";
import { notify } from "../../../sway_utils";

const InviteBody: React.FC = () => {
    const user = useUser();
    const link = useMemo(() => `${window.location.origin}${user.invite_url}`, [user.invite_url]);

    const handleCopy = useCallback(() => {
        copy(link, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied link to clipboard.",
                }),
        });
    }, [link]);

    return (
        <div>
            <p className="mb-2">The more friends you invite, the more Sway you earn.</p>

            <p className="mt-2">Invite your friends using this link:</p>
            <Button variant="link" className="p-0 ellipses mt-2" onClick={handleCopy}>
                <FiCopy title="Copy" onClick={handleCopy} />
                &nbsp;{link}
            </Button>
        </div>
    );
};

export default InviteBody;
