import { router, usePage } from "@inertiajs/react";
import BillCreatorLegislatorVotes from "app/frontend/components/admin/creator/BillCreatorLegislatorVotes";
import BillCreatorOrganizations from "app/frontend/components/admin/creator/BillCreatorOrganizations";
import BillCreatorBill from "app/frontend/components/admin/creator/BillCreatorBill";
import { EEventKey } from "app/frontend/components/bill/creator/constants";
import { PropsWithChildren, useCallback } from "react";
import { Accordion } from "react-bootstrap";
import { sway } from "sway";
import { notify } from "app/frontend/sway_utils";

interface IProps {
    setCreatorDirty: React.Dispatch<React.SetStateAction<boolean>>;
}

const BillCreatorAccordions: React.FC<IProps> = ({ setCreatorDirty }) => {
    const bill = usePage().props.bill as sway.IBill;
    const isNoBillId = !(bill?.id && bill.id > 0);
    const event_key = new URLSearchParams(window.location.search).get("event_key");

    const setEventKey = useCallback(
        (eventKey: EEventKey) => {
            if (eventKey !== EEventKey.BILL && isNoBillId) {
                notify({
                    level: "error",
                    title: "Click Save on the Details and Summary tab before proceeding.",
                });
                return;
            }

            const params = new URLSearchParams(window.location.search);
            if (eventKey === event_key) {
                params.delete("event_key", eventKey);
            } else {
                params.set("event_key", eventKey);
            }
            router.get(`${window.location.origin}${window.location.pathname}?${params.toString()}`);
        },
        [event_key, isNoBillId],
    );

    return (
        <Accordion activeKey={event_key}>
            <Accordion.Item eventKey={EEventKey.BILL}>
                <AccordionButton eventKey={EEventKey.BILL} onClick={setEventKey}>
                    Details and Summary
                </AccordionButton>

                <Accordion.Body>
                    <BillCreatorBill setCreatorDirty={setCreatorDirty} />
                </Accordion.Body>
            </Accordion.Item>

            <Accordion.Item eventKey={EEventKey.LEGISLATOR_VOTES}>
                <AccordionButton eventKey={EEventKey.LEGISLATOR_VOTES} onClick={setEventKey} disabled={isNoBillId}>
                    Legislator Votes
                </AccordionButton>

                <Accordion.Body>
                    <BillCreatorLegislatorVotes />
                </Accordion.Body>
            </Accordion.Item>

            <Accordion.Item eventKey={EEventKey.ORGANIZATIONS}>
                <AccordionButton eventKey={EEventKey.ORGANIZATIONS} onClick={setEventKey} disabled={isNoBillId}>
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
