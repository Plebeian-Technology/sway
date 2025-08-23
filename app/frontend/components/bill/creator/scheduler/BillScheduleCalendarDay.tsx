import { Tooltip } from "@mui/material";
import { PickersDay, PickersDayProps } from "@mui/x-date-pickers";
import { sway } from "sway";

export default function BillScheduleCalendarDay(
    props: PickersDayProps & { bill: sway.IBill | undefined; highlightedDays?: number[] },
) {
    const { bill, highlightedDays = [], day, outsideCurrentMonth, ...other } = props;

    const isSelected = !props.outsideCurrentMonth && highlightedDays.indexOf(day.getDate()) >= 0;

    return (
        <Tooltip title={bill?.title || "No Bill"}>
            <PickersDay
                key={day.toString()}
                {...other}
                outsideCurrentMonth={outsideCurrentMonth}
                day={day}
                className={isSelected ? "border border-primary-subtle" : undefined}
                sx={
                    isSelected
                        ? {
                              "&:hover": {
                                  color: "common.white",
                                  backgroundColor: "rgb(60, 110, 247)",
                              },
                          }
                        : undefined
                }
            />
        </Tooltip>
    );
}
