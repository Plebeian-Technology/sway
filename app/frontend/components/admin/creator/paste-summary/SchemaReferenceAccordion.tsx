import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "app/frontend/components/ui/accordion";
import { Button } from "app/frontend/components/ui/button";

interface IProps {
    schemaExample: string;
    onCopyExample: () => void;
}

// @lat: [[paste-summary-schema-example#Why PASTE_SUMMARY_SCHEMA_EXAMPLE is written by hand]]
const SchemaReferenceAccordion: React.FC<IProps> = ({ schemaExample, onCopyExample }) => {
    return (
        <Accordion type="single" collapsible data-testid="schema-reference-accordion">
            <AccordionItem value="schema">
                <AccordionTrigger>Schema reference</AccordionTrigger>
                <AccordionContent>
                    <pre className="overflow-x-auto rounded-md bg-secondary p-3 font-mono text-xs">{schemaExample}</pre>
                    <div className="mt-2">
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            onClick={onCopyExample}
                            data-testid="btn-copy-paste-summary-example"
                        >
                            Copy example
                        </Button>
                    </div>
                </AccordionContent>
            </AccordionItem>
        </Accordion>
    );
};

export default SchemaReferenceAccordion;
