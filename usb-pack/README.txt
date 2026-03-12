Open Sparrow USB Pack (Windows)
===============================

Primary entry points
--------------------
- one-click-deploy.cmd : start + install + open dashboard
- one-click-stop.cmd   : stop local services

Legacy entry compatibility
--------------------------
- 01-*.cmd is kept and forwards to one-click-deploy.cmd

Runtime notes
-------------
- UI listens on localhost:19000 (or next free port)
- Gateway uses port 18889
- If schtasks is denied, deployment uses gateway-fallback mode

Support
-------
- For manual mode, see root README-FIRST.txt and root 00-manual-start.txt
