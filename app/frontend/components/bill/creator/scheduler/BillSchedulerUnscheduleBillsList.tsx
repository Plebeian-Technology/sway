import { usePage } from "@inertiajs/react";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";
import { useMemo } from "react";
import { Button, ListGroup, ListGroupItem } from "react-bootstrap";
import { ISelectOption, sway } from "sway";

interface IProps {
    selectedBill: ISelectOption;
    handleSelectBill: (bill: sway.IBill, newParams?: Record<string, string>) => void;
}

const BillSchedulerUnscheduleBillsList: React.FC<IProps> = ({ selectedBill, handleSelectBill }) => {
    const bills = usePage().props.bills as sway.IBill[];
    const unscheduled = useMemo(() => bills.filter((b) => !b.scheduled_release_date_utc), [bills]);

    const { remove } = useSearchParams();

    return (
        <div>
            <h3>Unscheduled Bills</h3>
            <ListGroup>
                <ListGroupItem>
                    <div className="row align-items-center">
                        <div className="col-3 bold">&nbsp;</div>
                        <div className="col-3 bold">External ID</div>
                        <div className="col-6 bold">Title</div>
                    </div>
                </ListGroupItem>
                {unscheduled.map((bill, i) => {
                    return (
                        <ListGroupItem key={`${bill.external_id}-${i}`}>
                            <div className="row align-items-center">
                                <div className="col-3">
                                    <Button
                                        disabled={selectedBill.value === bill.id}
                                        variant={selectedBill.value === bill.id ? "primary" : "outline-primary"}
                                        onClick={() => {
                                            remove(BILL_SCHEDULER_PARAMS_KEY);
                                            handleSelectBill(bill, { [BILL_SCHEDULER_PARAMS_KEY]: "" });
                                        }}
                                    >
                                        Select
                                    </Button>
                                </div>
                                <div className="col-3">{bill.external_id}</div>
                                <div className="col-6">{bill.title}</div>
                            </div>
                        </ListGroupItem>
                    );
                })}
            </ListGroup>
        </div>
    );
};

export default BillSchedulerUnscheduleBillsList;
