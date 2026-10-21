# Midterm Mini-Project: Empirical Evidence Log

**Course:** CS 554 — Advanced Computer Networks / Cloud Computing
**Student Level:** Graduate (CS 554 Extension Included)
**Execution Date:** Fall 2026

---

## Evidence Section 1: Application Container Build & Test Suite

### 1.1 Docker Image Build

```bash
docker build -t cs554-midterm-app:1.0.0 -t cs554-midterm-app:latest .
```

```text
#0 building with "desktop-linux" instance using docker driver
#1 [internal] load build definition from Dockerfile
#1 DONE 0.2s
#2 [internal] load metadata for docker.io/library/node:22-alpine
#2 DONE 3.5s
#6 [1/4] FROM docker.io/library/node:22-alpine
#7 [2/4] WORKDIR /app
#8 [3/4] COPY package.json ./
#9 [4/4] COPY src ./src
#10 exporting to image
#10 naming to docker.io/library/cs554-midterm-app:1.0.0 done
#10 naming to docker.io/library/cs554-midterm-app:latest done
#10 DONE 0.9s
```

### 1.2 Automated Containerized Unit Tests

```bash
docker run --rm -v "${PWD}:/workspace" -w /workspace cs554-midterm-app:1.0.0 npm test
```

```text
> cs454-midterm-starter@1.0.0 test
> node --test test/service.test.js

TAP version 13
# {"method":"GET","path":"/","status":200}
# {"method":"GET","path":"/health","status":200}
# {"method":"POST","path":"/health/unready","status":200}
# {"method":"GET","path":"/health","status":503}
# {"method":"POST","path":"/health/ready","status":200}
# {"method":"GET","path":"/health","status":200}
# {"method":"GET","path":"/","status":200}
# {"method":"GET","path":"/missing","status":404}
# {"method":"GET","path":"/","status":200}
# Subtest: configured responses, local counter, health, and fresh instance
ok 1 - configured responses, local counter, health, and fresh instance
  ---
  duration_ms: 344.737159
  type: 'test'
  ...
1..1
# tests 1
# suites 0
# pass 1
# fail 0
```

---

## Evidence Section 2: Docker Compose inside Linux VM (Part 2)

### 2.1 Compose Service Status inside Linux VM (Ubuntu 24.04 on Hyper-V)

```bash
docker compose ps
```

```text
NAME                    IMAGE                     COMMAND                  SERVICE   CREATED          STATUS          PORTS
cs554-compose-service   cs554-midterm-app:1.0.0   "docker-entrypoint.s…"   web       14 seconds ago   Up 14 seconds   0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
```

### 2.2 Endpoint Verification inside Linux VM (Loopback)

```bash
curl -i http://localhost:8080/
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:23:52 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"service":"cs554-compose-node","message":"Hello from Docker Compose inside Linux VM!","hostname":"b0c91ef01b6d","requestCount":1}
```

```bash
curl -i http://localhost:8080/health
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:23:52 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"status":"ok"}
```

### 2.3 Host-to-VM Requests from Windows Host

```powershell
curl.exe -i http://localhost:8080/
curl.exe -i http://localhost:8080/health
curl.exe -i http://localhost:8080/
curl.exe -i http://localhost:8080/
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:36:03 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"service":"cs554-compose-node","message":"Hello from Docker Compose inside Linux VM!","hostname":"418786f4cb57","requestCount":1}

HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:36:03 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"status":"ok"}

HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:36:03 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"service":"cs554-compose-node","message":"Hello from Docker Compose inside Linux VM!","hostname":"418786f4cb57","requestCount":2}

HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:36:03 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"service":"cs554-compose-node","message":"Hello from Docker Compose inside Linux VM!","hostname":"418786f4cb57","requestCount":3}
```

### 2.4 Service Restart & Local Counter Reset

```bash
docker compose restart web
curl.exe -i http://localhost:8080/
```

```http
Container cs554-compose-service  Restarting
Container cs554-compose-service  Started

HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:36:24 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"service":"cs554-compose-node","message":"Hello from Docker Compose inside Linux VM!","hostname":"418786f4cb57","requestCount":1}
```

*Observation:* Volatile process memory was cleared; request count reset from 3 to 1 while container hostname persisted.

### 2.5 Standard Output Container Logs

```bash
docker compose logs
```

```text
cs554-compose-service  | Listening on port 8080
cs554-compose-service  | {"method":"GET","path":"/","status":200}
cs554-compose-service  | {"method":"GET","path":"/health","status":200}
cs554-compose-service  | {"method":"GET","path":"/","status":200}
cs554-compose-service  | {"method":"GET","path":"/","status":200}
cs554-compose-service  | Received SIGTERM; stopping.
cs554-compose-service  | Listening on port 8080
cs554-compose-service  | {"method":"GET","path":"/","status":200}
```

---

## Evidence Section 3: Kubernetes Deployment & Resilience (Part 3)

### 3.1 Image Import into k3d Cluster

```bash
k3d image import cs554-midterm-app:1.0.0 -c midterm-cluster
```

```text
INFO[0000] Importing image(s) into cluster 'midterm-cluster' 
INFO[0001] Saving 1 image(s) from runtime...          
INFO[0015] Importing images into nodes...             
INFO[0015] Importing images from tarball into node 'k3d-midterm-cluster-server-0'... 
INFO[0053] Successfully imported 1 image(s) into 1 cluster(s)
```

### 3.2 Two Ready Replicas & Service Status

```bash
kubectl get deployment,pods,svc,endpointslices -l app=cs554-web
```

```text
NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cs554-web-deployment   2/2     2            2           52s

NAME                                        READY   STATUS    RESTARTS   AGE
pod/cs554-web-deployment-676c756f66-4mfcd   1/1     Running   0          52s
pod/cs554-web-deployment-676c756f66-vzj68   1/1     Running   0          52s

NAME                        TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/cs554-web-service   ClusterIP   10.43.195.23   <none>        8080/TCP   52s

NAME                                                     ADDRESSTYPE   PORTS   ENDPOINTS              AGE
endpointslice.discovery.k8s.io/cs554-web-service-gbn99   IPv4          8080    10.42.0.10,10.42.0.9   52s
```

### 3.3 Traffic Access through Kubernetes Service

```bash
kubectl port-forward svc/cs554-web-service 8085:8080
curl.exe -i http://localhost:8085/
curl.exe -i http://localhost:8085/health
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:42:27 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"service":"cs554-k8s-service","message":"Hello from CS 554 Kubernetes Deployment!","hostname":"cs554-web-deployment-676c756f66-4mfcd","requestCount":1}

HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:42:28 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"status":"ok"}
```

### 3.4 Pod Deletion & Automated Replica Replacement

```bash
kubectl get pods -l app=cs554-web
kubectl delete pod cs554-web-deployment-676c756f66-4mfcd
kubectl get pods -l app=cs554-web
```

```text
=== CURRENT PODS BEFORE DELETION ===
NAME                                    READY   STATUS    RESTARTS   AGE
cs554-web-deployment-676c756f66-4mfcd   1/1     Running   0          114s
cs554-web-deployment-676c756f66-vzj68   1/1     Running   0          114s

=== DELETING ONE POD ===
pod "cs554-web-deployment-676c756f66-4mfcd" deleted from default namespace

=== PODS IMMEDIATELY AFTER DELETION (RECONCILIATION DETECTED) ===
NAME                                    READY   STATUS              RESTARTS   AGE
cs554-web-deployment-676c756f66-sk6cq   0/1     ContainerCreating   0          1s
cs554-web-deployment-676c756f66-vzj68   1/1     Running             0          116s

=== RETURN TO TWO READY REPLICAS ===
NAME                                    READY   STATUS    RESTARTS   AGE
cs554-web-deployment-676c756f66-sk6cq   1/1     Running   0          6s
cs554-web-deployment-676c756f66-vzj68   1/1     Running   0          2m1s
```

---

## Evidence Section 4: Controlled Failure & Troubleshooting (Part 4)

### 4.1 Injection: Selector Mismatch (`app: cs554-web-mismatch`)

```bash
kubectl apply -f k8s/service.yaml
```

```text
service/cs554-web-service configured
```

### 4.2 Diagnostic Evidence of Failure

```bash
kubectl get pods --show-labels
kubectl describe svc cs554-web-service | grep -E "Selector|Endpoints"
kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service
```

```text
NAME                                    READY   STATUS    RESTARTS   AGE     LABELS
cs554-web-deployment-676c756f66-sk6cq   1/1     Running   0          42s     app=cs554-web,pod-template-hash=676c756f66
cs554-web-deployment-676c756f66-vzj68   1/1     Running   0          2m37s   app=cs554-web,pod-template-hash=676c756f66

Selector:                 app=cs554-web-mismatch
Endpoints:              

NAME                      ADDRESSTYPE   PORTS     ENDPOINTS   AGE
cs554-web-service-gbn99   IPv4          <unset>   <unset>     2m38s
```

### 4.3 Client Symptom

```bash
kubectl run test-client --image=curlimages/curl --restart=Never --rm -i --command -- curl --connect-timeout 3 -i http://cs554-web-service:8080/
```

```text
curl: (7) Failed to connect to cs554-web-service:8080 after 34 ms: Could not connect to server
pod "test-client" deleted from default namespace
```

### 4.4 Recovery Verification

```bash
# Selector reverted to app: cs554-web
kubectl apply -f k8s/service.yaml
kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service
kubectl run test-recovery --image=curlimages/curl --restart=Never --rm -i --command -- curl -i http://cs554-web-service:8080/
```

```text
service/cs554-web-service configured

NAME                      ADDRESSTYPE   PORTS   ENDPOINTS               AGE
cs554-web-service-gbn99   IPv4          8080    10.42.0.10,10.42.0.11   5m13s

HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:46:09 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"service":"cs554-k8s-service","message":"Hello from CS 554 Kubernetes Deployment!","hostname":"cs554-web-deployment-676c756f66-vzj68","requestCount":1}
```

---

## Evidence Section 5: CS 554 Live Readiness Probe Experiment

### 5.1 Baseline State

```bash
kubectl get pods -l app=cs554-web -o wide
kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service
```

```text
NAME                                    READY   STATUS    RESTARTS   AGE     IP           NODE                           NOMINATED NODE   READINESS GATES
cs554-web-deployment-676c756f66-sk6cq   1/1     Running   0          4m21s   10.42.0.11   k3d-midterm-cluster-server-0   <none>           <none>
cs554-web-deployment-676c756f66-vzj68   1/1     Running   0          6m16s   10.42.0.10   k3d-midterm-cluster-server-0   <none>           <none>

NAME                      ADDRESSTYPE   PORTS   ENDPOINTS               AGE
cs554-web-service-gbn99   IPv4          8080    10.42.0.10,10.42.0.11   6m16s
```

### 5.2 Failure Injection: One Pod Toggled Unready (Process Running, Not Crashed)

```bash
kubectl run toggle-off --image=curlimages/curl --restart=Never --rm -i --command -- curl -s -X POST http://10.42.0.11:8080/health/unready
```

```json
{"status":"ok","isReady":false,"message":"Instance marked NotReady"}
```

### 5.3 Diagnostic Evidence: Pod NotReady & EndpointSlice Exclusion

```bash
kubectl get pods -l app=cs554-web -o wide
kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service -o yaml
```

```yaml
# Pod Status:
NAME                                    READY   STATUS    RESTARTS   AGE     IP           NODE
cs554-web-deployment-676c756f66-sk6cq   0/1     Running   0          4m34s   10.42.0.11   k3d-midterm-cluster-server-0
cs554-web-deployment-676c756f66-vzj68   1/1     Running   0          6m29s   10.42.0.10   k3d-midterm-cluster-server-0

# EndpointSlice Conditions:
endpoints:
- addresses:
  - 10.42.0.10
  conditions:
    ready: true
    serving: true
    terminating: false
  targetRef:
    name: cs554-web-deployment-676c756f66-vzj68
- addresses:
  - 10.42.0.11
  conditions:
    ready: false
    serving: false
    terminating: false
  targetRef:
    name: cs554-web-deployment-676c756f66-sk6cq
```

*Key Finding:* Pod `sk6cq` remained in state `Running` with `RESTARTS: 0`. The process was never killed. The EndpointSlice controller cleanly set `ready: false, serving: false`.

### 5.4 Traffic Verification: In-Flight Client Routes Only to Healthy Backend

```bash
kubectl run test-traffic --image=curlimages/curl --restart=Never --rm -i --command -- curl -s -i http://cs554-web-service:8080/
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Date: Thu, 15 Oct 2026 03:47:28 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

{"service":"cs554-k8s-service","message":"Hello from CS 554 Kubernetes Deployment!","hostname":"cs554-web-deployment-676c756f66-vzj68","requestCount":2}
```

### 5.5 Recovery: Readiness Restored

```bash
kubectl run toggle-on --image=curlimages/curl --restart=Never --rm -i --command -- curl -s -X POST http://10.42.0.11:8080/health/ready
kubectl get pods -l app=cs554-web -o wide
kubectl get endpointslices -l kubernetes.io/service-name=cs554-web-service
```

```text
{"status":"ok","isReady":true,"message":"Instance marked Ready"}

NAME                                    READY   STATUS    RESTARTS   AGE     IP           NODE
cs554-web-deployment-676c756f66-sk6cq   1/1     Running   0          4m49s   10.42.0.11   k3d-midterm-cluster-server-0
cs554-web-deployment-676c756f66-vzj68   1/1     Running   0          6m44s   10.42.0.10   k3d-midterm-cluster-server-0

NAME                      ADDRESSTYPE   PORTS   ENDPOINTS               AGE
cs554-web-service-gbn99   IPv4          8080    10.42.0.10,10.42.0.11   6m44s
```
