// The admin catalog's focus handling with its elements in their own shadow
// roots (the pinned A2uiLitElement). See admin_focus_cases.mjs.

import {admin, mergedCatalog} from "./catalogs.mjs";
import {focusCases} from "./admin_focus_cases.mjs";

focusCases({mode: "shadow DOM", admin, mergedCatalog});
