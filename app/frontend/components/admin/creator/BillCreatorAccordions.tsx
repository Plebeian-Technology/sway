import { usePage } from "@inertiajs/react";
import BillCreatorBill from "app/frontend/components/admin/creator/BillCreatorBill";
import BillCreatorLegislatorVotes from "app/frontend/components/admin/creator/BillCreatorLegislatorVotes";
import BillCreatorOrganizations from "app/frontend/components/admin/creator/BillCreatorOrganizations";
import { EEventKey } from "app/frontend/components/bill/creator/constants";
import { notify } from "app/frontend/sway_utils";
import { PropsWithChildren, useCallback, useState } from "react";
import { Accordion } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    setCreatorDirty: React.Dispatch<React.SetStateAction<boolean>>;
}

const BillCreatorAccordions: React.FC<IProps> = ({ setCreatorDirty }) => {
    const bill = usePage().props.bill as sway.IBill;
    const isNoBillId = !(bill?.id && bill.id > 0);
    const [event_key, setEventKey] = useState<EEventKey | null>(
        new URLSearchParams(window.location.search).get("event_key") as EEventKey | null,
    );

    const handleSetEventKey = useCallback(
        (newEventKey: EEventKey) => {
            if (newEventKey !== EEventKey.BILL && isNoBillId) {
                notify({
                    level: "error",
                    title: "Click Save on the Details and Summary tab before proceeding.",
                });
                return;
            }

            if (newEventKey === event_key) {
                setEventKey(null);
            } else {
                setEventKey(newEventKey);
            }
        },
        [event_key, isNoBillId],
    );

    return (
        <Accordion activeKey={event_key}>
            <Accordion.Item eventKey={EEventKey.BILL}>
                <AccordionButton eventKey={EEventKey.BILL} onClick={handleSetEventKey}>
                    Details and Summary
                </AccordionButton>

                <Accordion.Body>
                    <BillCreatorBill setCreatorDirty={setCreatorDirty} />
                </Accordion.Body>
            </Accordion.Item>

            <Accordion.Item eventKey={EEventKey.LEGISLATOR_VOTES}>
                <AccordionButton
                    eventKey={EEventKey.LEGISLATOR_VOTES}
                    onClick={handleSetEventKey}
                    disabled={isNoBillId}
                >
                    Legislator Votes
                </AccordionButton>

                <Accordion.Body>
                    <BillCreatorLegislatorVotes />
                </Accordion.Body>
            </Accordion.Item>

            <Accordion.Item eventKey={EEventKey.ORGANIZATIONS}>
                <AccordionButton eventKey={EEventKey.ORGANIZATIONS} onClick={handleSetEventKey} disabled={isNoBillId}>
                    Supporting/Opposing Arguments
                </AccordionButton>

                <Accordion.Body>
                    <BillCreatorOrganizations />
                </Accordion.Body>
            </Accordion.Item>
        </Accordion>
    );
};

function AccordionButton({
    children,
    eventKey,
    disabled: _disabled,
    onClick,
}: PropsWithChildren & { eventKey: EEventKey; disabled?: boolean; onClick: (eKey: EEventKey) => void }) {
    return (
        <Accordion.Button onClick={() => onClick(eventKey)} className="py-4 fs-4">
            {children}
        </Accordion.Button>
    );
}

export default BillCreatorAccordions;
