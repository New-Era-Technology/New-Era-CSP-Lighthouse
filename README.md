For New Era to provide support services for any Azure environments, the tenants must be onboarded into the Azure Lighthouse program. By running this script, the customer can select which subscription(s) will be connected and eligible for support.

Script Requirements:

*   Requires PowerShell 7.1 or newer
*   Internet connection to Azure
*   Customer credentials with Contributor or higher to the in-scope subscriptions
*   Must be run from graphical UI, such as PowerShell ISE or PowerShell command line window. If there are more than one subscription in the tenant, this cannot be run from Cloud Shell due to use of Out-GridView

What it does:

*   Loads any necessary or missing Azure modules
*   Ingest the New Era maintained Lighthouse ARM Template and gathers required variables
*   Connects to customer tenant. User must provide credentials that have Contributor or higher.
*   If there is just one subscription in the tenant, it is selected and the ARM template is applied
*   If multiple subscriptions exist, the user can select one or more subscriptions to take action on.
*   Writes a CSV summary with per-subscription results.

How to use:

- Download Deploy-Lighthouse-Bulk.ps1 to your PC.
- Using a PowerShell 7.1 (minimum) window, chang to the path whwrw the file was downloaded.
- execute ".\Deploy-Lighthouse-Bulk.ps1"

Note: additional options are shown in the script

Interactive behavior:

\- when presented, log in with customer Azure credentials

![alt text](https://raw.githubusercontent.com/New-Era-Technology/New-Era-CSP-Lighthouse/refs/heads/main/images/1-signin.jpg?raw=true)

\- After login, select **any** subscription from the list. This is just for the session info and does not impact which tenant gets associated to Lighthouse.

![alt text](https://raw.githubusercontent.com/New-Era-Technology/New-Era-CSP-Lighthouse/refs/heads/main/images/2-loginsub.jpg?raw=true)

\- If the tenant has a single subscription, it will be auto-selected.

\- If multiple subscriptions exist, a selection popup is opened to choose subscriptions to process. Press and Hold the **Ctrl** key to multi select specific subscriptions.

![alt text](https://raw.githubusercontent.com/New-Era-Technology/New-Era-CSP-Lighthouse/refs/heads/main/images/3-selectsubs.jpg?raw=true)

\## Troubleshooting

\- Module installation requires network access to PSGallery and may require elevated privileges.

\- Out-GridView is not available in headless environments. If you need non-interactive runs, modify the script to accept a list of subscription IDs or run it where a GUI is available.

\- If provider registration times out, check subscription permissions and retry later.

\- Use \`-WhatIf\` first to validate the template and parameters without applying changes.
