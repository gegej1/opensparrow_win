Open Sparrow Local Deploy Pack (Windows)
=======================================

Quick Start (recommended)
-------------------------
1. Double-click: one-click-deploy.cmd
2. Wait until you see: [done] Deployment completed
3. Browser will open the dashboard automatically

Stop Services
-------------
- Double-click: one-click-stop.cmd

If you only distribute usb-pack
-------------------------------
- Start: usb-pack\one-click-deploy.cmd
- Stop : usb-pack\one-click-stop.cmd

Notes
-----
- On some Windows machines, schtasks permission is restricted.
- In that case, runtimeMode=gateway-fallback is expected and still works.
- If API key is missing, setup page will open for manual input.
- Manual fallback guide: 00-manual-start.txt
