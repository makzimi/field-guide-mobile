# Field Guide shared acceptance contract

These are fictional, hand-authored inputs and expected observations for
Field Guide. They are the single
editable source for both platform suites. Expected values in `scenarios.json`
were entered from the approved rules, not computed from Android or Flutter code.

## Files and vocabulary

- `catalog-valid.json` is the shipped starting catalog.
- `catalog-boundary.json` isolates the 60/61-minute rule.
- `catalog-changed.json` removes `canal-gardens`, closes `pine-loop` and adds
  `river-walk`.
- `catalog-invalid-*.json` are complete snapshots that must be rejected as a
  unit. Each declares why it is invalid. Most isolate one defect; `fields`
  deliberately combines two. They never replace a valid cache. Every invalid
  snapshot includes a valid `new-valid` row, which must not leak into the UI.
- `catalog-long-text.json` supplies a deterministic layout stress case.
- `catalog-sort-ties.json` puts equal-duration, equal-normalized-title rows in
  deliberately unsorted source order, so all three sort keys are observable.
- `scenarios.json` names all 17 acceptance scenarios and gives ordered actions
  with hand-authored observable assertions after each named step.

Each catalog is a top-level object with `fixtureId`, `kind: catalog`, and
`walks`. A walk has a stable ASCII ID, nonblank title and description, positive
integer duration in minutes and distance in metres, `terrain`, `availability`
and `artKey`. The valid terrain vocabulary is `woodland`, `garden`, `waterside`,
`ridge`; availability is `open` or `closed`; art keys are `pine`, `glasshouse`,
`canal`, `ridge`. These explicit R1 fixture values establish the paired sample's
supported mapper vocabulary. Invalid fixtures deliberately break it.

All scenario clocks are fake monotonic milliseconds. `fetchedAtMs` is the time
of the last **valid, winning** snapshot. Age 299999 ms is fresh and age 300000
ms is stale. `catalogFixture: null` means no in-memory snapshot. `savedIds`
represent persisted local IDs even if absent from a catalog. `storage: loading`
means those IDs are not yet available to the UI. `listIds` is visible order
after search and budget; `storedIds` is the persistent set; `savedCount` counts
only saved IDs present in the current catalog, independently of list filters.

`startRefresh` creates a named request. A subsequent `completeCatalog` or
`failCatalog` with its `requestId` resolves it. An older request may finish but
must not publish data, timestamp or error. `refreshWithFixture` abbreviates an
explicit refresh and completion with the stated fixture. A completion without
`requestId` resolves the one implicit request begun by `openList` or `retryCatalog`.
`resetHarness` discards in-memory state and pending requests, then installs its
explicit `initial` test state; it is not a product action. `sourceRequestCount`
counts starts since that reset. Input to each platform mapper is only `walks`;
`fixtureId`, `kind`, and `invalidBecause` are test metadata, never signals that
production code may use to accept or reject data.

`startSave` and `startRemove` begin atomic writes. `completeSave` gives their
success or failure, and `retrySave` retries the pending intent. `storedIds` is
the durable adapter state; `savedIds` in `initial` seeds that adapter, even while
`storage: loading` keeps it inaccessible to presentation state. `savedCount:
null` means unavailable, not zero. `savedActionsEnabled` is a global storage
readiness gate; `addEnabled` and `removeEnabled` are route-specific affordances.
`duplicateTap` asserts that a second save during one pending write creates no
new storage write. Expected objects are exact assertions for listed fields;
omitted fields are unconstrained. Their string state/reason values are semantic
contract values; platforms may render localized copy while retaining meaning.

`setClock` changes fake monotonic time and flushes due expiry notifications
before assertions. `foreground` rechecks the same time on resume.
`invokeAddUseCase` calls policy directly, bypassing the disabled UI action.
Therefore CLOCK-01 checks both visible expiry and execution-time protection.
For VIEW-01, `descriptionReachableByScroll` means the full text can be reached
without clipping, not that it fits at once. The portrait test viewport is
393×852 logical dp, text scale 1.6, in both light and dark themes.

VIEW-01 defines expectations for rendered and semantics tests. Static fixture
validation cannot establish clipping, reachability, accessibility or runtime
behavior. Platform fixture smoke tests only prove both suites can load the
same source. Behavior tests and device journeys verify separate parts of the
contract.

Run `python3 samples/contract/validate.py --report verification/contract-check.txt`
from the project root. The validator uses only the standard library, checks
file structure, fixture/scenario references, ID uniqueness, validity labels,
action structure and exact 60/61-minute and 299999/300000-ms boundaries.
