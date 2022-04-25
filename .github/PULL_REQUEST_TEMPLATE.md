## Motivation

<!--
Explain the context and why you're making that change. What is the problem
you're trying to solve? In some cases there is not a problem and this can be
thought of as being the motivation for your change.
-->

## Solution

<!--
Summarize the solution and provide any necessary context needed to understand
the code change.
-->

## Implementer Checklist

<!--
Fill out the checklist below as applicable to your change. Bug fixes and new features must 
check off all of the required items.
-->


- [ ]  [FIRST TIME ONLY] Review the [Solcurity](https://github.com/Rari-Capital/solcurity) standard
- [ ]  [OPTIONAL] Create a reference implementation (in python or JS)
- [ ]  Create a short "Motivation" section for the PR
- [ ]  Write a spec for the feature and put it in the PR description – basic function names and expected state transitions is OK
- [ ]  Check all of the new revert paths with concrete tests
- [ ]  Check all of the new storage slot writes with concrete tests – do not make the passing test case the trivial case!
- [ ]  Go line-by-line through the new code and ensure it has all been covered by concrete tests – since we don’t have a coverage engine for foundry yet, you can imagine how one might check that each different code path is covered
- [ ]  Simplify the implementation and spend some time trying to minimize gas costs
- [ ]  Write fuzz tests for the feature – try everything to break the implementation (is this function monotonically in/decreasing, should it always be less than something else, etc)
- [ ]  Capture bugs discovered during the above steps in concrete tests (regression tests)
- [ ]  Add integration tests – fuzz or concrete tests that test how the new code affects the entire system, either locally or with a mainnet fork
- [ ]  [OPTIONAL] Integrate the feature into the deployment scripts
- [ ]  [OPTIONAL] Add new sanity checks to the deployment scripts
- [ ]  Get the PR reviewed by at least two people