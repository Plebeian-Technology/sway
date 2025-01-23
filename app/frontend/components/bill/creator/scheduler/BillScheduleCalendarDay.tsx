import { Tooltip } from "@mui/material";
import { PickersDay, PickersDayProps } from "@mui/x-date-pickers";
import { getDate } from "date-fns";
import { sway } from "sway";

export default function BillScheduleCalendarDay(
    props: PickersDayProps<Date> & { bill: sway.IBill | undefined; highlightedDays?: number[] },
) {
    const { bill, highlightedDays = [], day, outsideCurrentMonth, ...other } = props;

    day.setMinutes(day.getMinutes() + day.getTimezoneOffset());

    const isSelected = !props.outsideCurrentMonth && highlightedDays.indexOf(getDate(day)) >= 0;

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
