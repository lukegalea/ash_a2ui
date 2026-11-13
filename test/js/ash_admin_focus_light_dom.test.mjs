// The admin catalog's focus handling with its elements rendered into light
// DOM, as the upstream @a2ui/lit renders custom-catalog elements. See
// admin_focus_cases.mjs.

import {admin, mergedCatalog} from "./light_dom_catalogs.mjs";
import {focusCases} from "./admin_focus_cases.mjs";

focusCases({mode: "light DOM", admin, mergedCatalog});
