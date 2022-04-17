import { ContentCopy } from "@mui/icons-material";
import { IconButton, SvgIconTypeMap, Tooltip } from "@mui/material";
import { OverridableComponent } from "@mui/material/OverridableComponent";
import { SWAY_COLORS } from "../../utils";

interface IProps {
    title: string;
    text: string;
    handleCopy: (text: string) => void;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
}

const LegislatorCardSocialItem: React.FC<IProps> = ({ title, text, handleCopy, Icon }) => {
    const setCopy = () => {
        handleCopy(text);
    };

    return (
        <div className="col">
            <span className="row" onClick={setCopy}>
                <span className="ellipses">{text}</span>
            </span>
            <span className="row align-items-center">
                <div className="col-3">
                    <IconButton
                        style={{
                            padding: 8,
                            backgroundColor: SWAY_COLORS.primary,
                        }}
                    >
                        <Icon style={{ color: SWAY_COLORS.white }} />
                    </IconButton>
                </div>
                <div className="col-3">
                    <Tooltip title={`Copy ${title}`} placement="right" onClick={setCopy}>
                        <ContentCopy />
                    </Tooltip>
                </div>
            </span>
        </div>
    );
};

export default LegislatorCardSocialItem;
