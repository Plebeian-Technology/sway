import { createStyles, InputLabel, makeStyles } from "@material-ui/core";
import "../../scss/checkbox.scss";
import { SWAY_COLORS } from "../../utils";

interface IProps {
    name: string;
    id: string;
    label: string | JSX.Element;
    checked: boolean;
    disabled?: boolean;
    onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
}

const useStyles = makeStyles(() =>
    createStyles({
        "MuiFormLabel-root": {
            color: SWAY_COLORS.black,
            paddingLeft: 40,
            paddingTop: 10,
        },
    }),
);

const SwayCheckbox: React.FC<IProps> = ({
    name,
    id,
    label,
    checked,
    disabled,
    onChange,
}) => {
    const classes = useStyles();
    return (
        <InputLabel
            className={`checkbox-container ${classes["MuiFormLabel-root"]}`}
        >
            <input
                className={"sway-checkbox"}
                type={"checkbox"}
                name={name}
                id={id}
                disabled={disabled ? disabled : false}
                checked={checked}
                onChange={onChange}
            />
            <span className="checkmark"></span>
            {label}
        </InputLabel>
    );
};

export default SwayCheckbox;
