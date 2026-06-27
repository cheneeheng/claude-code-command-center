/* ===================================================================
   Vantage v3 — bootstrap (loaded LAST)
   The only file that touches the DOM on boot. Every Vantage module must be
   loaded before this in index.html (load order is the dependency contract).
   =================================================================== */

'use strict';

window.addEventListener('DOMContentLoaded', () => { window.Vantage.UI.init(); });
