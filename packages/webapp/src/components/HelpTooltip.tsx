import { OverlayTrigger, Popover } from "react-bootstrap";
import { Placement } from "react-bootstrap/esm/types";
import { FiHelpCircle } from "react-icons/fi";

interface IProps {
    message: string | React.ReactNode;
    tooltipId: string;
    title?: string | React.ReactNode;
    size?: string;
    hideLabel?: boolean;
    placement?: Placement;
    className?: string;
}

const HelpTooltip: React.FC<IProps> = ({
    message,
    tooltipId,
    title,
    size,
    hideLabel,
    placement,
    className,
}) => {
    return (
        <div>
            {!title && (
                <div className={`ml-1 mb-1 ${className}`}>
                    <OverlayTrigger
                        key="top"
                        placement={placement || "top"}
                        overlay={
                            <Popover id={tooltipId}>
                                <Popover.Header as="h3">Details</Popover.Header>
                                <Popover.Body>{message}</Popover.Body>
                            </Popover>
                        }
                    >
                        <FiHelpCircle fontSize={size ? size : undefined} className="blue" />
                    </OverlayTrigger>
                </div>
            )}
            {title && (
                <div className={`row no-gutters ${className}`}>
                    {!hideLabel && <span>{title}</span>}
                    <div className="ml-1 mb-1">
                        <OverlayTrigger
                            key="top"
                            placement={placement || "top"}
                            overlay={
                                <Popover id={tooltipId}>
                                    <Popover.Header as="h3">{title}</Popover.Header>
                                    <Popover.Body>{message}</Popover.Body>
                                </Popover>
                            }
                        >
                            <FiHelpCircle fontSize={size ? size : undefined} className="blue" />
                        </OverlayTrigger>
                    </div>
                </div>
            )}
        </div>
    );
};

export default HelpTooltip;
