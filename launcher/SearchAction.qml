// Search-bar action button. Providers expose a `searchActions` list of
// these; the launcher renders one button per entry on the right of the
// search bar while the provider is active. Clicking emits `triggered`.

import QtQuick

QtObject {
    property string icon: ""    // glyph shown in the button (e.g. "+")
    property string name: ""    // human label — tooltip/aria copy
    signal triggered()
}
