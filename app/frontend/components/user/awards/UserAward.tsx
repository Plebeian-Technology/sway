import { AWARDS, AWARD_ICONS } from "app/frontend/sway_constants";
import { useCallback, useState } from "react";
import { Badge, Image } from "react-bootstrap";
import { FiAward } from "react-icons/fi";

interface IProps {
    index: number;
}

// const DEFAULT_AWARD_ICON = <FiAward />;
const DEFAULT_AWARD_ICON = "default";

const UserAward: React.FC<IProps> = ({ index }) => {
    const [icon, setIcon] = useState<string>(AWARD_ICONS[index] || DEFAULT_AWARD_ICON);

    const handleIconError = useCallback(() => {
        setIcon((current) => (current === DEFAULT_AWARD_ICON ? current : DEFAULT_AWARD_ICON));
    }, []);

    return (
        <div className="row align-items-center my-1">
            <div className="col-2 col-sm-2 col-md-1 col-lg-1 col-xl-1 ps-0">
                {icon === DEFAULT_AWARD_ICON ? (
                    <Badge className="p-2">
                        <FiAward />
                    </Badge>
                ) : (
                    <Image src={icon} alt={"award"} roundedCircle thumbnail className="p-0" onError={handleIconError} />
                )}
            </div>
            <div className="col-10 col-sm-10 col-md-11 col-lg-11 col-xl-11 px-0">&nbsp;{AWARDS[index]}</div>
        </div>
    );
};

export default UserAward;
