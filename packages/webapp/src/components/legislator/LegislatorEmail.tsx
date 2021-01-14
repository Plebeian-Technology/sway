import { Tooltip, Typography } from "@material-ui/core";
import { EmailOutlined } from "@material-ui/icons";
import { isPhoneWidth } from "../../utils";

interface IProps {
    email: string;
    handleCopy: (email: string) => void;
}

const LegislatorEmail: React.FC<IProps> = ({ email, handleCopy }) => {
    return (
        <div
            style={{
                justifyContent: isPhoneWidth ? "flex-start" : "center",
            }}
            className={
                "legislator-card-sub-card-header legislator-card-copy-group"
            }
            onClick={() => handleCopy(email)}
        >
            <div className={"legislator-card-sub-card-header-item"}>
                <EmailOutlined />
            </div>
            <div className={"legislator-card-sub-card-header-item"}>
                <Typography variant={"body2"}>{email}</Typography>
            </div>
            <div className={"legislator-card-row-break"} />
            <Tooltip title="Copy Email" placement="right">
                <div className={"legislator-card-sub-card-header-item"}>
                    <img
                        alt={"copy button"}
                        src={"/copy.png"}
                        className={"legislator-card-copy-icon"}
                    />
                </div>
            </Tooltip>
        </div>
    );
};

export default LegislatorEmail;
