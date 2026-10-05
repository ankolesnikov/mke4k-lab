# Configuration reference

[← Back to README](../README.md)

All settings live in `config` (sourced by bash). Child-cluster settings are in [child-cluster.md](child-cluster.md#child-cluster-settings).

## Shared infrastructure

| Variable | Default | Description |
|---|---|---|
| `cluster_name` | `mke4k-lab` | Name prefix for all resources. Left as default, the first `t deploy lab\|instances` asks for your name (interactive terminal only; sanitised to a-z, 0-9, max 10 chars) → `mke4k-lab-<name>` plus an `Owner` tag on every resource; non-interactive runs (or an empty answer) get a random 4-char suffix (e.g. `mke4k-lab-a3f2`). Persisted in `.cluster-id` / `.owner`. Set an explicit name (≤ 20 chars) to skip the prompt |
| `controller_count` | `1` | Number of controller nodes (use 3 for HA) |
| `worker_count` | `1` | Number of worker nodes |
| `controller_flavor` | `m5a.xlarge` | EC2 instance type for controllers |
| `worker_flavor` | `m5a.large` | EC2 instance type for workers |
| `region` | `eu-central-1` | AWS region |
| `expiry_days` | `3` | Auto-delete the whole lab this many days after creation unless `t destroy lab` runs first (`0` = never). A reaper (EventBridge Scheduler → Lambda) runs inside AWS, so it fires even if the container is gone. Change it on a live lab with `t expiry <days>` / `t expiry off`. Does not cover child clusters |
| `expiry_dry_run` | `false` | When `true`, the reaper only logs (CloudWatch) what it would delete instead of deleting it — for checking its scope. It takes effect at the next apply of the reaper (`t deploy lab\|instances`, or `t expiry <days>`), not by editing `config` alone. **With `false`, invoking the Lambda by hand deletes the lab**; check first with `aws lambda get-function-configuration --function-name <cluster_name>-reaper --query Environment.Variables.DRY_RUN`, then `aws lambda invoke --function-name <cluster_name>-reaper /dev/stdout` |
| `os_name` | `ubuntu` | Cluster node OS: `ubuntu` or `redhat` (bastion/NFS server always Ubuntu) |
| `os_version` | `22.04` | Node OS version — MKE4-supported: ubuntu `22.04`/`24.04`, redhat `9.6`/`8.10` (others warn) |
| `ccm_enabled` | `false` | Creates IAM role; required for LoadBalancer services. Auto-disabled in airgap |
| `debug` | `true` | `true` adds `-l debug` to mkectl (all modes including airgap) |

## MKE4k settings

| Variable | Default | Description |
|---|---|---|
| `mke4k_version` | `v4.2.0` | MKE4k / mkectl version |

## MKE3 settings

| Variable | Default | Description |
|---|---|---|
| `launchpad_version` | `1.5.15` | Launchpad binary version (no `v` prefix) |
| `mke3_version` | `3.8.2` | MKE3 version |
| `mcr_version` | `25.0.14` | MCR (Docker engine) version |
| `mcr_channel` | `stable-25.0.14` | Must match `mcr_version` exactly |
| `mke3_admin_username` | `admin` | MKE3 UI admin user |

## Airgap settings

| Variable | Default | Description |
|---|---|---|
| `airgap_registry_flavor` | `t3.xlarge` | EC2 instance type for the bastion/registry host |
| `airgap_registry_disk_gb` | `100` | Root volume size (GB) for bastion (Harbor data + bundle) |
| `airgap_msr_version` | `v4.13.3` | MSR4 (Harbor) offline installer version |
| `mke4k_bundle_url` | *(auto)* | Override the MKE4k bundle download URL |
| `mke3_bundle_url` | *(auto)* | Override the MKE3 image bundle download URL |

## NFS settings

| Variable | Default | Description |
|---|---|---|
| `nfs_enabled` | `true` | Provisions NFS server EC2, installs nfs-common on nodes, deploys nfs-subdir-external-provisioner |
| `nfs_flavor` | `t3.small` | EC2 instance type for the NFS server |
| `nfs_disk_gb` | `150` | Root volume size (GB) for the NFS server. Sized with headroom for KOF's VictoriaMetrics/Logs/Traces PVCs, which land on `nfs-client` |
| `nfs_export_path` | `/srv/nfs/data` | NFS export path on the server |

## MSR4 settings

| Variable | Default | Description |
|---|---|---|
| `msr4_enabled` | `false` | Enables `t deploy msr4` / `t deploy msr4 airgap` (standalone; not auto-run during `t deploy lab`) |
| `msr4_version` | `4.13.3` | Harbor chart version deployed on the cluster (separate from `airgap_msr_version` which controls the bastion registry) |
| `msr4_replicas` | `1` | `1` = simple (built-in DB+Redis); `>=2` = HA (postgres-operator + redis-operator). HA requires `worker_count >= msr4_replicas` |
| `msr4_postgres_version` | `1.15.1` | Zalando postgres-operator chart version (HA only) |
| `msr4_redis_operator_version` | `0.24.0` | OT-Container-Kit redis-operator chart version (HA only) |
| `msr4_redis_replication_version` | `0.16.13` | OT-Container-Kit redis-replication chart version (HA only) |
| `msr4_storage_size` | `10Gi` | PVC size for the MSR4 registry volume (requires `nfs_enabled=true`) |

## KOF settings

| Variable | Default | Description |
|---|---|---|
| `kof_enabled` | `false` | Auto-deploy KOF (self-monitoring/M2M) at the end of `t deploy lab` / `t deploy lab airgap`. Even when `false`, KOF can be deployed later with `t deploy kof` / `t deploy kof airgap`. Requires a StorageClass |
| `kof_mode` | `lean` | Deployment scope: `full` (complete observability + FinOps platform) or `lean` (cluster monitoring only). Override per-run: `t deploy kof full` / `t deploy kof lean` |
| `kof_version` | `1.8.1` | KOF Helm umbrella-chart version (matches k0rdent Enterprise 1.3.2 / MKE 4.2.0) |
| `kof_storage_size` | `10Gi` | PVC size for the VictoriaMetrics / VictoriaLogs / VictoriaTraces volumes (doc default is 100Gi) |
| `kof_storage_ha` | `true` | Keep VictoriaMetrics/VictoriaLogs in HA (cluster) topology. Applies to both modes |
| `kof_registry` | `registry.mirantis.com/k0rdent-enterprise` | Image/chart registry. In airgap it is auto-derived to `<registry-hostname>/mke`; override only for a different custom registry |
| `kof_kcm_namespace` | `k0rdent` | Namespace where k0rdent (KCM) runs. KOF's upstream default is `kcm-system`, but MKE4k's k0rdent Enterprise uses `k0rdent`; the KOF Flux objects + KCM integration are created here |
| `kof_grafana_enabled` | `true` | Deploy Grafana (grafana-operator + datasources/dashboards + the `kof/grafana.yaml` instance CR). Grafana is no longer shipped with KOF by default |
| `kof_grafana_image_tag` | `11.0.0` | Grafana image tag in `<kof_registry>/grafana/grafana` (the registry ships `11.0.0`, not the doc's `10.4.18-security-01`) |
| `kof_grafana_gateway_enabled` | `true` | Expose Grafana over HTTPS via a dedicated Envoy Gateway + NLB listener (requires `kof_grafana_enabled`). **Touches terraform** online — `t deploy kof` runs `terraform apply`. In airgap the gateway is auto-enabled regardless (access via `t tunnel grafana`) |
| `kof_grafana_nodeport` | `33002` | NodePort the Grafana Envoy gateway is pinned to (opened in the cluster SG; NLB target group forwards here). Range 32768-35535 |
| `kof_grafana_lb_port` | `8443` | NLB listener port for Grafana (TCP pass-through; the gateway terminates TLS). In airgap this is the local port of `t tunnel grafana` |
| `kof_reuse_mke_monitoring` | `true` | Reuse MKE4's built-in monitoring instead of duplicating it (drops KOF's node-exporter + kube-proxy/coredns/apiserver scrapes, KSM custom-resource-only, adds MKE's Prometheus as Grafana datasource) |
| `kof_reuse_mke_kubelet` | `true` | Sub-option of reuse: also drop KOF's duplicate kubelet/cAdvisor scrape so pod CPU/memory aren't double-counted (~2x otherwise) |
| `kof_sf_notifier_enabled` | `false` | Route alerts with severity critical\|warning\|error to the sf-notifier webhook. sf-notifier itself is deployed separately by hand — leave `false` unless it is running |
| `kof_lean_prune_folders` | `Istio,Opencost,Victoria Traces` | Lean mode: Grafana dashboard folders to drop (comma-separated) |
| `kof_lean_prune_dashboards` | `kps-nodes-aix,kps-nodes-darwin` | Lean mode: individual dashboards to drop (comma-separated) |

## k0rdent UI settings

| Variable | Default | Description |
|---|---|---|
| `k0rdent_ui_enabled` | `false` | Publish the k0rdent UI at the end of `t deploy lab` / `t deploy lab airgap`; also required for `t deploy k0rdent-ui`. **Touches terraform** (NLB listener + SG rule) |
| `k0rdent_ui_nodeport` | `33003` | NodePort the Envoy gateway is pinned to (range 32768-35535; 33001/33002/33443 taken) |
| `k0rdent_ui_lb_port` | `8445` | NLB listener port (online) / local port of `t tunnel k0rdent-ui` (airgap) |
