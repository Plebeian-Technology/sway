import { PickersDay, PickersDayProps } from "@mui/x-date-pickers";
import { Dayjs } from "dayjs";

export default function BillScheduleCalendarDay(props: PickersDayProps<Dayjs> & { highlightedDays?: number[] }) {
    const { highlightedDays = [], day, outsideCurrentMonth, ...other } = props;

    const isSelected = !props.outsideCurrentMonth && highlightedDays.indexOf(props.day.date()) >= 0;

    return (
        <PickersDay
            key={props.day.toString()}
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
    );
}
