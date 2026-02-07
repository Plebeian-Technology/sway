import { Tooltip } from "@mui/material";
import { sway } from "sway";

interface IBillScheduleCalendarDayProps {
    bill: sway.IBill | undefined;
    highlightedDays?: number[];
    day: Date;
    outsideCurrentMonth?: boolean;
    selected?: boolean;
    onDaySelect: (day: Date) => void;
}

export default function BillScheduleCalendarDay(props: IBillScheduleCalendarDayProps) {
    const { bill, highlightedDays = [], day, outsideCurrentMonth, selected, onDaySelect } = props;

    const isHighlighted = !outsideCurrentMonth && highlightedDays.indexOf(day.getDate()) >= 0;
    const isToday =
        day.getDate() === new Date().getDate() &&
        day.getMonth() === new Date().getMonth() &&
        day.getFullYear() === new Date().getFullYear();

    let className = "btn btn-sm w-100 h-100 d-flex align-items-center justify-content-center p-0 rounded-circle";
    if (selected) {
        className += " btn-primary text-white";
    } else if (isHighlighted) {
        className += " border border-primary-subtle text-primary bg-light";
    } else if (isToday) {
        className += " border border-primary text-primary";
    } else {
        className += " btn-light bg-transparent text-dark";
    }

    if (outsideCurrentMonth) {
        className += " text-muted opacity-50";
    }

    return (
        <Tooltip title={bill?.title || "No Bill"}>
            <button
                type="button"
                className={className}
                onClick={() => onDaySelect(day)}
                style={{ width: "36px", height: "36px", fontSize: "0.875rem" }}
            >
                {day.getDate()}
            </button>
        </Tooltip>
    );
}
