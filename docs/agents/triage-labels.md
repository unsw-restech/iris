# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Default label role         | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

A ticket goes to `ready-for-agent` only if an agent can meet every acceptance criterion on its own. A criterion that needs someone outside the session, such as an org owner or a ResTech administrator, names who in the criterion, and the ticket goes to `ready-for-human` unless the rest is worth building first (#99).

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the "Label in our tracker" column to match whatever vocabulary you actually use.

## Proposals

A proposal arrives through the issue form (`.github/ISSUE_TEMPLATE/proposal.yml`), which applies `proposal` and not `needs-triage`; ordinary issues keep the triage labels above.

| Label      | Meaning                                                        |
| ---------- | -------------------------------------------------------------- |
| `proposal` | A workflow author's proposal to add a workflow, not yet built  |
| `approved` | The maintainer approved the proposal; the author can build it  |

The maintainer approves with a comment and `approved`, or declines by closing with `wontfix`, pointing at the approval criteria on the contribute page.
