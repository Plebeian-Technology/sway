import { lazy, Suspense, useCallback, useState } from "react";
import { Button } from "react-bootstrap";
import { FiShare2 } from "react-icons/fi";

const ShareDialog = lazy(() => import("./ShareDialog"));

const ShareButtons: React.FC = () => {
    const [isOpen, setOpen] = useState<boolean>(false);

    const handleOpen = useCallback(() => setOpen(true), []);
    const handleClose = useCallback(() => setOpen(false), []);

    return (
        <>
            <Button variant="outline-primary" onClick={handleOpen} size="lg" style={{ flex: 1 }}>
                <FiShare2 />
                &nbsp;Share
            </Button>
            <Suspense fallback={null}>
                <ShareDialog isOpen={isOpen} handleClose={handleClose} />
            </Suspense>
        </>
    );
};

export default ShareButtons;
