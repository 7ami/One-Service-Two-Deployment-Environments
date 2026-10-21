# CS 454/554 Mini-Project Technical Report & OpenStack Analysis
**Course:** CS 554 — Advanced Computer Networks / Cloud Computing  
**Topic:** One Service, Two Deployment Environments (Docker Compose in Linux VM vs. Kubernetes Cluster) & OpenStack Deployment Analysis  
**Student Level:** Graduate (CS 554 Extension Included)  

---

## 1. Architectural System Overview & Network Topologies

This project demonstrates the containerization, deployment, failure diagnosis, and lifecycle orchestration of a lightweight HTTP service across two distinct virtualization abstractions:
1. **Environment A:** Docker Compose running inside a Linux Virtual Machine (Hyper-V / Ubuntu 24.04 LTS).
2. **Environment B:** A local Kubernetes cluster (k3s / k3d v5.9.0) with replica management, resource boundaries, and active readiness probes.

### Architectural Diagram: Multi-Layer Request Flow

```
========================================================================================
                                     WINDOWS HOST
                      Client Browser / PowerShell curl / Test Scripts
========================================================================================
                 |                                                |
    [Path A: Docker Compose]                         [Path B: Kubernetes Cluster]
                 |                                                |
                 v                                                v
+-----------------------------------+             +-----------------------------------+
|            LINUX VM               |             |          k3d CLUSTER              |
|   (Ubuntu 24.04 LTS on Hyper-V)   |             |   (k3s Server on Docker Engine)   |
|   VM IP: 172.27.166.183           |             |   Node: k3d-midterm-cluster-srv-0 |
|                                   |             |                                   |
| +-------------------------------+ |             | +-------------------------------+ |
| | Docker Engine & docker-proxy  | |             | | K8s Service (ClusterIP: 8080) | |
| | Published Port: 0.0.0.0:8080  | |             | | Selector: app=cs554-web       | |
| +---------------+---------------+ |             | +---------------+---------------+ |
|                 |                 |             |                 |                 |
|                 v (Bridge NAT)    |             |                 v (kube-proxy /   |
| +-------------------------------+ |             |                    EndpointSlice) |
| | Container: cs554-compose-svc  | |             |         +-------+-------+         |
| | Node.js Process (:8080)       | |             |         |               |         |
| | Local requestCount memory     | |             |         v               v         |
| +-------------------------------+ |             |   +-----------+   +-----------+   |
+-----------------------------------+             |   | Pod 1     |   | Pod 2     |   |
                                                  |   | 10.42.0.10|   | 10.42.0.11|   |
                                                  |   | Node.js   |   | Node.js   |   |
                                                  |   | (:8080)   |   | (:8080)   |   |
                                                  |   +-----------+   +-----------+   |
                                                  |   (Requests: 50m / Limits: 200m)  |
                                                  |   (Readiness Probe: /health)      |
                                                  +-----------------------------------+
```

---

## 2. Environment Comparison: Docker Compose (VM) vs. Kubernetes

| Architectural Dimension | Docker Compose in Linux VM | Kubernetes Deployment & Service |
| :--- | :--- | :--- |
| **Abstractions Managed** | Single host daemon managing local container processes and bridge network. | Distributed declarative controller managing Pods, ReplicaSets, Services, and EndpointSlices. |
| **Process Failure Recovery** | `restart: unless-stopped` triggers the local Docker daemon to restart the same container entity. | Controller-Manager reconciliation loop detects Pod absence or death and provisions an entirely new replacement Pod with a fresh identity and IP. |
| **State & Memory Lifecycle** | Restarting the container clears volatile in-process memory (`requestCount` resets from 3 to 1). Host identity persists. | Deleting a Pod destroys the container instance completely. The replacement Pod receives a new ephemeral IP and zeroed in-process memory. |
| **Traffic Routing & Discovery**| Static DNAT / `docker-proxy` port mapping (`host_port:container_port`). Direct 1-to-1 forward. | Dynamic Service abstraction backed by EndpointSlices and `kube-proxy` iptables/IPVS rules decoupling frontend from ephemeral backend IPs. |
| **Health Checking & Readiness**| Docker healthcheck monitors container health; can restart unhealthy containers if configured. | Decouples liveness (restarting a dead container) from readiness (routing traffic only when application is ready to serve). |

---

## 3. Controlled Troubleshooting & Root Cause Analysis (Part 4)

### Baseline Configuration & Failure Injection
- **Baseline:** Service selector matched Pod labels (`app: cs554-web`). Both replicas (`10.42.0.10`, `10.42.0.11`) were ready. `EndpointSlice` listed both IP endpoints. HTTP client requests to `http://cs554-web-service:8080/` succeeded with HTTP 200 OK.
- **Controlled Change:** Modified `k8s/service.yaml` selector to an unmatched label: `app: cs554-web-mismatch`. The underlying Deployment template was kept completely healthy and untouched.

### Observed Symptoms & Diagnostic Hierarchy
1. **Client Symptom:** In-cluster clients issuing requests to the Service received immediate connection failure:
   ```
   curl: (7) Failed to connect to cs554-web-service:8080 after 34 ms: Could not connect to server
   ```
   Clients attempting to establish a new `kubectl port-forward svc/cs554-web-service 8086:8080` were blocked with `error: no pods found for service cs554-web-service`.
2. **Diagnostic Evidence Collected:**
   - **Pod Status:** `kubectl get pods -l app=cs554-web` verified both Pods were healthy (`STATUS: Running`, `READY: 1/1`).
   - **Pod Labels vs. Service Selector:** Pods possessed `app=cs554-web`, whereas `kubectl describe svc cs554-web-service` revealed `Selector: app=cs554-web-mismatch`.
   - **EndpointSlice Inspection:** `kubectl get endpointslices` revealed `ENDPOINTS: <unset>` and `PORTS: <unset>`. Because the endpoint controller found zero Pods matching the selector, it stripped all routing targets from the Service.

### Root Cause & Academic Explanation
A Kubernetes Service does not route traffic directly to Pod specifications; rather, the **EndpointSlice controller** continuously monitors the apiserver, evaluates the Service selector against active Pod labels, and populates the `EndpointSlice` data structure. `kube-proxy` reads this EndpointSlice to configure node packet-filtering rules (iptables or IPVS). 

Even when container processes and Pods are 100% operational and healthy, **traffic cannot reach them if the label-selector coupling is broken**. Healthy Pods merely prove that the application process is running inside its Linux cgroup/namespace; they do *not* guarantee network reachability through the Service abstraction.

### Recovery Verification
Reverted the Service selector to `app: cs554-web` and applied the manifest. Immediately:
- EndpointSlice repopulated with `10.42.0.10, 10.42.0.11`.
- Client test execution (`test-recovery`) connected instantly and received HTTP 200 OK (`requestCount: 1`, `hostname: cs554-web-deployment-676c756f66-vzj68`).

---

## 4. CS 554 Extension: Resource Boundaries & Readiness Probe Experiment

### Resource Settings Interpretation
In `k8s/deployment.yaml`, the container was configured with:
```yaml
resources:
  requests:
    cpu: "50m"
    memory: "64Mi"
  limits:
    cpu: "200m"
    memory: "128Mi"
```
- **Requests vs. Limits Distinction:**
  - A **Resource Request** (`50m` CPU, `64Mi` memory) is the guaranteed quantity of compute resources that the Kubernetes `kube-scheduler` requires to place a Pod onto a worker node. If a node cannot satisfy the sum of container requests, the Pod remains `Pending`.
  - A **Resource Limit** (`200m` CPU, `128Mi` memory) is the hard upper ceiling enforced by the Linux kernel cgroups runtime (`cgroupv2`). For CPU, the CFS (Completely Fair Scheduler) throttles container thread cycles if the limit is exceeded. For memory, if the container resident set size (RSS) breaches 128Mi, the Linux kernel invokes the Out-Of-Memory (OOM) killer to terminate the violating process (`OOMKilled`, exit code 137).
- **Engineering Justification:** Lightweight Node.js microservices possess a minimal V8 runtime memory baseline of ~30–40MiB and near-zero idle CPU. Setting a request of 64MiB prevents over-allocation and enables dense node packing, while the 128MiB limit protects shared host memory against potential asynchronous memory leaks.

### Live Readiness Probe Experiment
Kubernetes readiness probes decouple container liveness from traffic eligibility.
- **Probe Specification:** `httpGet: path: /health, port: 8080`, `periodSeconds: 3`, `failureThreshold: 2`, `successThreshold: 1`.
- **Baseline Observation:** Both replicas (`10.42.0.10` and `10.42.0.11`) were in state `READY: 1/1, Running`. EndpointSlice contained both IP addresses marked `ready: true, serving: true`.
- **Failure Injection (Non-Destructive):** Toggled the application-level readiness state of Pod `10.42.0.11` via `POST /health/unready`. Subsequent `GET /health` requests returned HTTP 503 Service Unavailable.
- **Diagnostic Evidence:**
  - `kubectl get pods`: Pod `cs554-web-deployment-676c756f66-sk6cq` transitioned to `READY: 0/1, STATUS: Running`. Crucially, `RESTARTS: 0` remained unchanged, proving the process was never killed or crashed.
  - `kubectl get endpointslices -o yaml`: Pod `10.42.0.11` was dynamically updated to `ready: false, serving: false`.
  - Service Traffic: Consecutive HTTP client requests to `cs554-web-service:8080` routed 100% of incoming traffic to healthy replica `10.42.0.10` without a single dropped packet or 503 error returned to the client.
- **Recovery:** Toggled the endpoint via `POST /health/ready`. Upon the next successful probe check (3s), the Pod transitioned back to `READY: 1/1` and the EndpointSlice immediately restored `10.42.0.11` to `ready: true, serving: true`.

---

## 5. Part 5: OpenStack Cloud Deployment Analysis (Technical Essay)

### 5.1 Architecture, Resources, and Choices
Deploying this containerized workload onto an OpenStack Infrastructure-as-a-Service (IaaS) cloud requires provisioning compute, image, identity, and software-defined networking (SDN) resources:

1. **Glance Image:** A base cloud image such as `Ubuntu-24.04-LTS-cloudimg` (qcow2 format), preconfigured with `cloud-init` and `cloud-utils`.
2. **Nova Flavor:** A modest flavor such as `m1.small` (1 vCPU, 2048 MB RAM, 20 GB root disk). A microservice of this scale consumes negligible CPU and ~60MB RAM; allocating more than 1–2 GB RAM would waste shared cloud capacity.
3. **Nova Key Pair:** An SSH public key injected via Nova metadata into `/home/ubuntu/.ssh/authorized_keys` for secure operator administration.
4. **Neutron Tenant Network & Subnet:** An isolated private virtual L2/L3 network (e.g., `app-internal-net`, subnet `192.168.100.0/24`) with DHCP enabled to assign private IP addresses to virtual instances.
5. **Neutron Virtual Router & External Gateway:** A virtual router (`app-router`) linking the private tenant subnet interface to the cloud administrator's external provider network (e.g., `public-net` / floating IP pool) using source NAT (SNAT).
6. **Neutron Floating IP:** A public, routable IP address allocated from the external pool and mapped via 1-to-1 NAT (DNAT) to the virtual machine’s fixed private IP (`192.168.100.x`).
7. **Neutron Security Group (`app-secgroup`):** A stateful firewall controlling ingress traffic.
8. **Administrative vs. Tenant Scope:** The tenant creates the private network, subnet, router, instance, security group rules, and allocates a floating IP. The cloud administrator provides the external physical provider network, the floating IP subnet pool, base Glance images, and hardware compute flavors.
9. **Cinder Persistent Block Storage Evaluation:** Persistent block storage via Cinder is **not required** for this particular stateless workload. The service stores its request counter purely in volatile process RAM and writes logs to standard output. Ephemeral instance disk is entirely sufficient.

### 5.2 OpenStack Service Responsibilities & Lifecycle
When orchestrating the instance:
- **Keystone (Identity):** Authenticates the tenant's credentials, issues a scoped JSON Web Token (JWT), and verifies RBAC permissions across the service catalog endpoints.
- **Glance (Image):** Serves the immutable Ubuntu base image metadata and transfers image chunks from its storage backend (e.g., Ceph RBD or Swift) to the hypervisor.
- **Nova (Compute):** The `nova-scheduler` applies filter algorithms (RAMFilter, CoreFilter, AvailabilityZoneFilter) to select a physical compute node, and the local `nova-compute` driver instructs libvirt/KVM to instantiate the virtual machine domain.
- **Neutron (Networking):** Provisions virtual network tap devices, creates Open vSwitch (OVS) or Linux Bridge ports, attaches the instance vNIC to the tenant VXLAN/Geneve overlay network, configures DHCP, and applies security group firewall filtering rules.
- **Post-Boot Orchestration:** Once the VM boots, `cloud-init` user-data executes a shell script that installs Docker and Docker Compose, fetches our `docker-compose.yml`, and executes `docker compose up -d`.

### 5.3 End-to-End Request Path & Firewall Rules
Tracing an external client HTTP request:
1. **External Client Request:** Client sends `GET http://<FLOATING_IP>:8080/`.
2. **Edge Ingress & Gateway:** The packet enters the OpenStack external provider gateway and arrives at the Neutron virtual router.
3. **Neutron 1-to-1 DNAT:** The virtual router translates the destination IP from `<FLOATING_IP>` to the VM's fixed tenant IP (`192.168.100.15`).
4. **Virtual Overlay Routing:** The packet travels across the Neutron overlay network (GENEVE/VXLAN tunnel encapsulation across physical compute hosts) to the hypervisor hosting the VM.
5. **Security Group Filtering:** Before the packet reaches the VM's TAP interface, Neutron's stateful firewall (implemented via Open vSwitch connection tracking or Linux iptables/nftables) evaluates ingress rules. To permit application traffic, an ingress rule must explicitly allow:
   - **Direction:** Ingress
   - **Ethertype:** IPv4
   - **Protocol:** TCP
   - **Port Range:** 8080
   - **Remote CIDR:** `0.0.0.0/0` (or restricted client CIDR).  
   *Note:* This rule is strictly distinct from the rule required for administrative SSH access (TCP port 22) and optional ICMP diagnostic ping (Echo Request type 8, code 0).
6. **VM Guest & Docker Proxy:** The packet traverses the guest OS `eth0` interface. Linux `iptables` and `docker-proxy` perform DNAT forwarding the packet to the bridge network interface (`172.18.0.2:8080`).
7. **Container Execution:** The Node.js HTTP server receives the TCP stream, parses `GET /`, increments `requestCount`, outputs JSON log entry to stdout, and sends the HTTP 200 response back through the return NAT path.

### 5.4 Layered Failure Analysis: Inaccessible Service Diagnosis
If the Nova instance shows `ACTIVE`, but an external client cannot reach `http://<FLOATING_IP>:8080/`, troubleshooting must proceed systematically from inner application layers to outer cloud infrastructure layers:

```
[Level 1: Application & Container] -> [Level 2: VM Operating System] -> [Level 3: OpenStack Cloud Network]
```

1. **Layer 1: Application Process & Container State (inside VM)**
   - *Action:* SSH into the VM (`ssh -i key.pem ubuntu@<FLOATING_IP>`) and check `docker compose ps` and `docker compose logs`.
   - *Evidence Collected:* Container state (Up vs. Restarting/Exited), container stderr logs, listening sockets (`ss -tlpn | grep 8080`). Test local loopback: `curl -i http://localhost:8080/`. If this fails, the bug is within the application crash or port binding.
2. **Layer 2: VM Guest Networking & Host Firewall**
   - *Action:* Check internal IP binding (`ip addr show eth0`), default routing gateway (`ip route`), and guest OS firewall (`sudo ufw status` or `sudo iptables -L -n`).
   - *Evidence Collected:* Verify guest OS allows incoming traffic on port 8080 and that default gateway points to Neutron router (`192.168.100.1`).
3. **Layer 3: Cloud Virtual Network & Security Controls (Neutron / Nova)**
   - *Action:* Check OpenStack CLI/Horizon: `openstack server show`, `openstack floating ip show`, and `openstack security group rule list <secgroup>`.
   - *Evidence Collected:*
     - Verify Floating IP is correctly mapped to the VM's port.
     - Verify `app-secgroup` contains an ingress rule for TCP 8080 (omitting this rule is the most common cause of timeouts).
     - Test ICMP ping: if ping succeeds but port 8080 hangs, Neutron routing works, isolating the fault to missing security group port rules.
     - Inspect virtual router interface status and compute node OVS flow tables.

### 5.5 Operational Complexity: Infrastructure Operator vs. Application Deployer
Operating an OpenStack cloud is orders of magnitude more complex than deploying an application into a functional cloud. 
- **The Application Deployer** interacts only with standardized REST API contracts (Keystone token, Nova boot call, Neutron port creation), assuming underlying physical compute, SAN storage, and top-of-rack switches are synchronized.
- **The Cloud Operator** must maintain the distributed control plane: message queue brokers (RabbitMQ) handling RPC state between Nova components, relational state databases (Galera MySQL clusters), Ceph distributed storage daemons (OSDs, MONs), and software-defined network agents (OVS agents, L3 agents, DHCP agents) across dozens of physical hypervisors.
- **Real-World Incident Example:** During multi-node OpenStack maintenance, if a RabbitMQ cluster loses quorum or an NTP clock skew exceeds 50 milliseconds across hypervisors, Nova compute agents fail heartbeat checks. While the underlying virtual machine and guest container continue running normally, tenant API requests to attach volumes or allocate floating IPs fail catastrophically. This constitutes an **infrastructure provider failure**, completely separate from an application deployment defect.

### 5.6 Synthesis: VM + Compose vs. Kubernetes
A single Linux VM with Docker Compose is suitable for small-scale development, single-tenant internal tools, or simple low-traffic services where high availability is unnecessary and brief downtime during host patching is acceptable. 

However, as demonstrated in our experiments, Kubernetes provides critical enterprise capabilities that Compose lacks:
1. **Self-Healing Replication:** Automatically detecting and recreating replacement Pods upon node or process termination to guarantee target replica counts.
2. **Dynamic Endpoint Management:** Decoupling service endpoints from volatile IP addresses via EndpointSlices.
3. **Traffic Gating via Readiness Probes:** Ensuring failing, slow-starting, or overloaded replicas are isolated from incoming client traffic without killing the process, preserving service uptime and user experience.

