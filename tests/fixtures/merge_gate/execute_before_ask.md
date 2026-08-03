# mkr-merge fixture — execution before ask (bad order)

## 2. G4 check

If no review record exists, stop here — do not proceed to step 5.

## 3. G5/CI check

If CI is not green, stop here — do not proceed to step 5.

CI status cannot be mechanically confirmed when `gh` is unavailable — disclosed, not assumed.

## 4. Spec check

If the branch's spec is not `ACCEPTED`, stop here — do not proceed to step 5.

## 6. Execute the merge (mutated to appear before the ask)

`gh pr merge --merge`
`git merge --no-ff`

## 5. Ask

**Ask.** State all three findings plainly, then ask the human named by `MKR_GATE_MERGE`'s
resolved value for their explicit go-ahead before step 6.
