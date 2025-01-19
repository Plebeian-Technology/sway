import { usePage } from "@inertiajs/react";
import { BILL_SCHEDULER_PARAMS_KEY } from "app/frontend/components/bill/creator/scheduler/constants";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";
import { getDate, getYear } from "date-fns";
import { useMemo } from "react";
import { Button, ListGroup, ListGroupItem } from "react-bootstrap";
import { ISelectOption, sway } from "sway";

interface IProps {
    selectedBill: ISelectOption;
    handleSelectBill: (bill: sway.IBill, newParams?: Record<string, string>) => void;
}

const today = new Date();

const BillSchedulerUpcomingBills: React.FC<IProps> = ({ selectedBill, handleSelectBill }) => {
    const bills = usePage().props.bills as sway.IBill[];
    const upcoming = useMemo(
        () =>
            bills.filter((b) => {
                const d = new Date(b.scheduledReleaseDateUtc);
                return b.scheduledReleaseDateUtc && getDate(d) >= getDate(today) && getYear(d) >= getYear(today);
            }),
        [bills],
    );

    const { remove } = useSearchParams();

    return (
        <div>
            <h3>Scheduled/Upcoming Bills</h3>
            <ListGroup>
                <ListGroupItem>
                    <div className="row align-items-center">
                        <div className="col-3 bold">&nbsp;</div>
                        <div className="col-3 bold">Release Date</div>
                        <div className="col-3 bold">External ID</div>
                        <div className="col-6 bold">Title</div>
                    </div>
                </ListGroupItem>
                {upcoming.map((bill, i) => {
                    return (
                        <ListGroupItem key={`${bill.externalId}-${i}`}>
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
                                <div className="col-3">{bill.scheduledReleaseDateUtc}</div>
                                <div className="col-3">{bill.externalId}</div>
                                <div className="col-6">{bill.title}</div>
                            </div>
                        </ListGroupItem>
                    );
                })}
            </ListGroup>
        </div>
    );
};

export default BillSchedulerUpcomingBills;
