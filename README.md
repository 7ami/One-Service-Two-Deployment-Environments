# CS 454/554 Midterm Mini-Project
**One Service, Two Deployment Environments (Docker Compose in Linux VM & Kubernetes Cluster)**  
**Student Level:** CS 554 (Graduate Extension Included)  

---

## Video Walkthrough Recording Link
- **Walkthrough Video (3–5 min):** `[INSERT YOUR UNLISTED YOUTUBE / CLOUD RECORDING LINK HERE]`  

---

## Project Structure
```
midterm-project/
├── Dockerfile                  # Multi-environment OCI container image definition
├── docker-compose.yml          # Part 2: VM & Compose orchestration spec
├── .dockerignore               # Build context optimization
├── k8s/
│   ├── deployment.yaml         # Part 3 & CS 554: Deployment (2 replicas, limits, readiness probe)
│   └── service.yaml            # Part 3 & 4: Service (ClusterIP, port 8080)
├── src/
│   └── server.js               # Node.js HTTP service (/ and /health endpoints + toggle)
├── test/
│   └── service.test.js         # Automated unit & integration tests
├── REPORT.md                   # Technical Report, comparison, and OpenStack analysis
├── EVIDENCE.md                 # Labeled terminal output logs and observation data
└── README.md                   # Build, run, test, and reproducibility guide
```

---

## 1. Prerequisites & Toolchain
- **Host Machine:** Windows 10/11
- **Virtualization:** Linux Virtual Machine (Ubuntu 24.04 LTS on Hyper-V / WSL2)
- **Container Engine:** Docker Engine 29.x, Docker Compose v2.x
- **Kubernetes Cluster:** k3d v5.9.0 (running lightweight k3s v1.35.x)
- **Client Tools:** `curl`, `kubectl`, PowerShell / bash

---

## 2. Environment A: Docker Compose inside Linux VM

### 2.1 Build & Start Service
Inside the Linux VM:
```bash
# Navigate to the project directory
cd /path/to/midterm-project

# Start the service in the background
docker compose up -d --build

# Verify container status and logs
docker compose ps
docker compose logs
```

### 2.2 Access & Verification
- **Inside the VM:**
  ```bash
  curl -i http://localhost:8080/
  curl -i http://localhost:8080/health
  ```
- **From the Windows Host:**
  ```powershell
  # Using host-to-VM port mapping (localhostForwarding / NAT)
  curl.exe -i http://localhost:8080/
  curl.exe -i http://localhost:8080/health
  ```

### 2.3 Process Restart & Counter Reset Observation
```bash
# Restart the container process
docker compose restart web

# Request from host to observe requestCount reset to 1
curl.exe -i http://localhost:8080/
```

### 2.4 Cleanup
```bash
docker compose down
```

---

## 3. Environment B: Local Kubernetes Cluster (k3d)

### 3.1 Cluster Initialization & Image Loading
```powershell
# 1. Create a local k3d Kubernetes cluster
k3d cluster create midterm-cluster --port 8082:80@loadbalancer

# 2. Build the Docker image on the host
docker build -t cs554-midterm-app:1.0.0 .

# 3. Import the image directly into the k3d cluster
k3d image import cs554-midterm-app:1.0.0 -c midterm-cluster
```

### 3.2 Deployment & Service Creation
```powershell
# Apply manifests
kubectl apply -f k8s/

# Verify 2 ready replicas and Service endpoints
kubectl get deployment,pods,svc,endpointslices -l app=cs554-web
```

### 3.3 Accessing the Service
```powershell
# Port-forward service port to local port 8085
kubectl port-forward svc/cs554-web-service 8085:8080

# In a separate terminal:
curl.exe -i http://localhost:8085/
curl.exe -i http://localhost:8085/health
```

### 3.4 Self-Healing Pod Replacement Experiment
```powershell
# Delete one Pod replica
kubectl delete pod <POD_NAME>

# Immediately observe controller reconciliation and replacement
kubectl get pods -l app=cs554-web
```

---

## 4. Part 4: Controlled Failure & Recovery

### 4.1 Introduce Failure (Selector Mismatch)
In `k8s/service.yaml`, change `selector.app` to `cs554-web-mismatch` and apply:
```powershell
kubectl apply -f k8s/service.yaml
```
- **Observe Symptoms:**
  ```powershell
  # Check EndpointSlices (Endpoints becomes <unset>)
  kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service
  
  # Client request fails with connection refused
  kubectl run test-client --image=curlimages/curl --restart=Never --rm -i --command -- curl --connect-timeout 3 -i http://cs554-web-service:8080/
  ```

### 4.2 Recovery
Restore `selector.app: cs554-web` in `k8s/service.yaml` and reapply:
```powershell
kubectl apply -f k8s/service.yaml

# Verify endpoints restored and client receives HTTP 200 OK
kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service
kubectl run test-recovery --image=curlimages/curl --restart=Never --rm -i --command -- curl -i http://cs554-web-service:8080/
```

---

## 5. CS 554 Extension: Live Readiness Probe Experiment

### 5.1 Failure Injection (Non-Destructive)
Trigger application unready state on Pod A without terminating its process:
```powershell
kubectl run toggle-off --image=curlimages/curl --restart=Never --rm -i --command -- curl -s -X POST http://<POD_A_IP>:8080/health/unready
```
- **Observe:**
  ```powershell
  # Pod A transitions to 0/1 Running (RESTARTS = 0)
  kubectl get pods -l app=cs554-web -o wide

  # EndpointSlice marks Pod A ready: false, serving: false
  kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service -o yaml

  # Client traffic seamlessly routes only to Pod B
  kubectl run test-traffic --image=curlimages/curl --restart=Never --rm -i --command -- curl -s -i http://cs554-web-service:8080/
  ```

### 5.2 Recovery
Restore readiness state on Pod A:
```powershell
kubectl run toggle-on --image=curlimages/curl --restart=Never --rm -i --command -- curl -s -X POST http://<POD_A_IP>:8080/health/ready

# Verify Pod A returns to 1/1 Running and eligible in EndpointSlice
kubectl get pods -l app=cs554-web -o wide
kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service
```

---

## 6. Complete Cluster Cleanup
```powershell
# Delete Kubernetes resources
kubectl delete -f k8s/

# Delete the k3d cluster
k3d cluster delete midterm-cluster

# Stop Compose service inside VM
wsl -u root bash -c "cd /mnt/c/Users/Abc/Downloads/First_sem/ICC/midterm-project && docker compose down"
```
