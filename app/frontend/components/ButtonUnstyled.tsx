import { Button, ButtonProps } from "react-bootstrap";

const ButtonUnstyled: React.FC<ButtonProps> = ({ children, ...props }) => {
    return (
        <Button variant="link" className="bg-transparent border-transparent shadow-none no-underline p-0" {...props}>
            {children}
        </Button>
    );
};

export default ButtonUnstyled;
