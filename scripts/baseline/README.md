# Karmada-native baseline (Approach B)

An AI-free counterpart to the WASP AI-driven placement (Approach A), built
**only** from Karmada mechanisms, so both approaches can be compared with the
same workloads (`simulator/data/input.json`), the same metrics pipeline
(monitor → `metrics.json`) and the same `analyzer/` plots.

## Behavioural contract (mirrors what the AI actuator actually does)

1. **A workload always lives whole in exactly one cluster** — the AI actuator
   (`recommendations-manager/orchestrators/karmada.go`) only ever flips a
   `cloud` label, moving all replicas together; it never splits them.
2. **member1 (private) is the default; member2 (public) is burst-only** — a
   workload only goes to member2 when member1 cannot host all of its replicas.
3. **No silent scheduling failure** — if at admission time no cluster fits the
   workload, real pods must still exist and show up as `Pending`
   (`kube_pod_status_phase{phase="Pending"}`), preferably in member2 so the
   Cluster Autoscaler gets its normal trigger to add nodes.

## Why this is non-trivial in stock Karmada

Karmada v1.14 couples one `replicaScheduling` mode to the whole placement:

* `Divided`+`Aggregated` is capacity-aware (rules 1–2) but returns
  `UnschedulableError` when **no** cluster fits — the ResourceBinding gets
  `Scheduled=False` and **zero pods are created anywhere** (violates rule 3,
  invisible to pod metrics).
* `Weighted`+`staticWeightList` never checks capacity (real pods → rule 3 OK)
  but divides replicas by weight (violates rule 1).
* `clusterAffinities` (ordered fallback groups) cannot mix modes per group.

## The mechanism

One `ClusterPropagationPolicy` (`baseline-policy.yaml`) plus three environment
adjustments (`setup_baseline.sh`) resolve the tension:

```
placement:
  clusterAffinities:
    - {affinityName: private-first, clusterNames: [member1]}
    - {affinityName: public-burst,  clusterNames: [member2]}
  replicaScheduling: {replicaSchedulingType: Divided, replicaDivisionPreference: Aggregated}
```

* **Rule 1** — each affinity group holds a single cluster, so Aggregated
  division is all-or-nothing per group; replicas can never straddle clusters.
  (`karmada-descheduler` is scaled to 0 because its partial evictions would
  reintroduce splits via scale-down rescheduling.)
* **Rule 2** — the scheduler walks the groups in order
  (`pkg/scheduler/scheduler.go`, `affinityIndex` loop): `private-first` is
  tried first and is genuinely capacity-checked, because
  `karmada-scheduler-estimator-member1` stays up and
  `calAvailableReplicas` (`pkg/scheduler/core/util.go`) takes the **minimum**
  over all estimators — the gRPC estimator gives a precise per-node,
  taint-aware answer for member1.
* **Rule 3** — `public-burst` can never fail:
  * `karmada-scheduler-estimator-member2` is scaled to 0. Per-cluster gRPC
    failures return `UnauthenticReplica`, which `calAvailableReplicas`
    *skips*, so member2's capacity comes from the **general estimator** only.
  * The general estimator reads `Cluster.Status.ResourceSummary`, which sums
    allocatable over **all** nodes, taints included
    (`cluster_status_controller.go, getClusterAllocatable`). The
    `member2-virtual-capacity` node (100000 CPU, tainted
    `virtual-capacity:NoSchedule`, ignored by workloads' tolerations, outside
    the Cluster Autoscaler nodegroup, filtered out of monitor queries) therefore makes
    member2 always look schedulable to Karmada — *modelling the elasticity
    of a public cloud* — while the member2 `kube-scheduler` still refuses to
    bind pods to it. Overflow pods stay genuinely `Pending`, and the Cluster
    Autoscaler reacts to them exactly as in production.
  * `CustomizedClusterResourceModeling=false` on `karmada-scheduler`: with
    the gate on (implied by `AllBeta=true`), the general estimator uses the
    resource-models path, which **ignores current usage** and caps the
    estimate at `nodes × grade-minimum` (~38 replicas here) — that would
    both starve member1 (premature bursts) and defeat the virtual node.
    With the gate off it uses the transparent
    `(allocatable − allocated − allocating) / request` summary path.

Known, documented asymmetries (all visible in the metrics — they are part of
what the comparison is meant to measure):

* The baseline never repatriates a workload from member2 back to member1
  (Karmada records `schedulerObservedAffinityName` and resumes from that
  group).
* Same-second bursts of creations can over-admit member1: the gRPC estimator
  does not count still-unbound pods, and the general estimator's `Allocating`
  term lags behind by the `ResourceSummary` refresh (~10 s), so several
  workloads admitted in that window can all "fit" the same free capacity.
  The losers land whole-workload `Pending` in member1 (no CA there) — Karmada
  considers their binding satisfied, and `karmada-descheduler` is disabled
  (its partial evictions would split workloads across clusters, breaking
  rule 1). This used to be a permanent gap (only the AI-driven approach could
  migrate them); it is now repaired by **`spec.failover.application`** on
  `baseline-policy.yaml`: once a
  cluster reports the workload `Unhealthy` (any Pending replica marks the
  *whole* Deployment unhealthy under the default resource interpreter) for
  longer than `decisionConditions.tolerationSeconds` (60s here), Karmada
  evicts that cluster from the binding and re-schedules the **entire**
  workload — landing it whole in member2, never split, unlike
  `karmada-descheduler`'s partial eviction. Caveats: it only self-heals
  Deployments (`batch/v1 Job` has no default health interpreter in this
  Karmada version) and it reacts on a delay (`tolerationSeconds` +
  `gracePeriodSeconds`), so workloads created very close to the end of a run
  may not have time to fail over before the simulator exits.

Between consecutive baseline runs, clear the previous run's workloads
(`make clean-workloads`) — the broker recreates the same names.

## Usage

```bash
make setup-and-start-baseline # everything: infra setup + setup-baseline + run-baseline
                              #             + plots + clean-workloads + teardown-baseline
```

Or step by step:

```bash
make setup-baseline   # switch the running environment to baseline mode
make run-baseline     # one simulation run, AI disabled (WASP_DISABLE_AI=1)
make teardown-baseline# restore the AI-driven configuration
```

`run-baseline` produces the usual run directory under
`simulator/data/output/<timestamp>/` (metrics.json + logs) plus
`unschedulable_bindings.jsonl`, a 30 s time series of ResourceBindings with
`Scheduled=False` — sampled by `simulator/internal/baseline.UnschedulablePoller`,
started from `cmd/main.go` whenever `WASP_DISABLE_AI` is set (nil/never started
for AI-driven runs). With the baseline working this stays at 0; the analyzer
(`analyzer/data_loader.py::load_unschedulable_data`) charges any non-zero
sample against the baseline, so a silent failure can never be mistaken for a
healthy run. Plots are generated automatically by the simulator itself for
both flows (a single, unconditional `analyzer.GeneratePlots(runDir)` call at
the end of `main()` — by then `unschedulable_bindings.jsonl` is already
written for baseline runs) — no separate `make -C analyzer generate-plots`
step is needed. Migration counts for baseline runs are inferred from
`metrics.json` snapshots (`analyzer/data_processor.py::detect_migrations_from_snapshots`),
since there is no actuator log.
