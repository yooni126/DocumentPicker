package com.fdp.documentpicker {
    import flash.external.ExtensionContext;
    /** Low-level ANE entry point. See the app-side IOSDocumentPicker adapter. */
    public final class DocumentPickerExtension {
        public static const ID:String = "com.fdp.DocumentPicker";
        public static function createContext():ExtensionContext {
            return ExtensionContext.createExtensionContext(ID, "");
        }
    }
}
