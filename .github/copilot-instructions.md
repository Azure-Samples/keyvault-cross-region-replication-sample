# Copilot Instructions for keyvault-cross-region-replication-sample

## Design Decisions

- The agreed architecture and design choices are documented in `README.md`.
- **Never change the fundamental design approach** (e.g., switching from export/import to backup/restore for key replication) without explicitly asking the user first.
- If a design documented in README.md turns out to be blocked by a technical issue, **stop and explain the blocker** to the user before proposing alternatives.
- When proposing alternatives, list the trade-offs and let the user decide.

## When Stuck

- **Do not guess or attempt random approaches.** If something doesn't work as expected, stop and research first.
- Before trying workarounds, use Microsoft documentation tools (e.g., `microsoft_docs_search`, `microsoft_docs_fetch`, Context7 library docs, or official Az module reference pages) to find the documented solution.
- If a PowerShell cmdlet is missing or has changed parameters in a newer module version, look up the current module documentation to find the correct replacement — do not iterate through trial and error.
- If no documented solution exists, inform the user with a clear explanation of what was tried and what the actual constraint is.

## Az.KeyVault Module

- This project targets **Az.KeyVault 6.x** (see `App/requirements.psd1`).
- Be aware that Az.KeyVault 6.x has breaking changes from earlier versions (removed cmdlets, renamed parameters).
- Always verify cmdlet availability and parameter names against the installed module version before writing code.

## Azure Resource Management

- **Do not generate random resource names on every run.** Use deterministic naming (e.g., derived from subscription ID) so repeated runs reuse the same resources instead of creating orphans.
- **Always clean up on failure.** If a deployment fails, delete the partially-created resource group before retrying with new names.
- **Use `Remove-TestEnvironment.ps1 -All`** to clean up all `rg-kvrep-test-*` resource groups if things get out of hand.
- Before re-running `Deploy-TestEnvironment.ps1`, check for and clean up any previous test environment (the script now does this automatically).
