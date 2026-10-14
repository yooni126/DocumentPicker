package examples {
    import com.fdp.documentpicker.DocumentPickerExtension;
    import flash.events.StatusEvent;
    import flash.external.ExtensionContext;

    /** Minimal picker interaction; add your own file-reading and parsing layer. */
    public class BasicUsage {
        private var context:ExtensionContext;

        public function openPicker():void {
            if (context == null) {
                context = DocumentPickerExtension.createContext();
                if (context == null) {
                    trace("Document Picker ANE unavailable");
                    return;
                }
                context.addEventListener(StatusEvent.STATUS, onStatus);
            }
            if (!Boolean(context.call("browseExcel"))) {
                trace("Document Picker is busy or cannot start");
            }
        }

        private function onStatus(event:StatusEvent):void {
            if (event.code == "SELECT") {
                // Parse event.level JSON and read its local file URL asynchronously.
                // ONLY AFTER the read finishes: context.call("releaseSelectedFile").
                // This example intentionally does not implement an Excel parser.
                trace("File selected; finish reading before cleanup");
            } else if (event.code == "ERROR") {
                trace("Document picker error: " + event.level);
            } else if (event.code == "CANCEL") {
                trace("Document picker cancelled");
            }
        }

        public function dispose():void {
            if (context == null) return;
            context.call("cancel");
            context.removeEventListener(StatusEvent.STATUS, onStatus);
            context.dispose();
            context = null;
        }
    }
}
