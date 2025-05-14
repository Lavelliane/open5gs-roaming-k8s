# Open5GS Roaming Deployment Summary (Two Clusters with NodePort SEPPs)

This document summarizes the steps taken to deploy a 5G roaming scenario using Open5GS Helm charts, simulating separate home and visited networks potentially across different Kubernetes clusters (using Minikube IP and NodePorts for SEPP N32 communication).

**Goal:** Achieve a roaming setup with Open5GS deployed in `home-network` and `visited-network` namespaces, using SEPPs for inter-network communication via N32, and simulating a UE with PacketRusher.

**Prerequisites:**
*   Two Kubernetes clusters (or namespaces simulating them). Minikube was used here.
*   `kubectl` configured for the cluster(s).
*   Helm v3 installed.
*   `minikube tunnel` running in a separate terminal (if using Minikube for LoadBalancer service exposure).
*   Local checkout of the Gradiant `5g-charts` repository.

**Key Configuration Files Created:**
*   `home-sepp-values.yaml`: Custom values for the Home SEPP.
*   `visited-sepp-values.yaml`: Custom values for the Visited SEPP.
*   `packetrusher-values.yaml`: Custom values for PacketRusher.
*   `add-subscriber-job.yaml`: Kubernetes Job to add the home subscriber.

**Deployment Steps:**

1.  **Namespace Creation:**
    ```bash
    kubectl create namespace home-network
    kubectl create namespace visited-network
    ```

2.  **Deploy Home Network MongoDB:**
    *   Installed MongoDB separately first to manually add subscriber later.
    *   Disabled all other Open5GS NFs initially.
    *   Used MongoDB image `4.4.15` due to compatibility issues with later versions (e.g., `5.0.x`, `4.4.18`).
    *   Increased MongoDB probe timeouts to avoid premature readiness failures.
    ```bash
    helm install home-open5gs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.0 \
      --namespace home-network \
      --set populate.enabled=false \
      --set hss.enabled=false \
      --set mme.enabled=false \
      --set pcrf.enabled=false \
      --set sgwc.enabled=false \
      --set sgwu.enabled=false \
      --set amf.enabled=false \
      --set smf.enabled=false \
      --set upf.enabled=false \
      --set ausf.enabled=false \
      --set bsf.enabled=false \
      --set nrf.enabled=false \
      --set nssf.enabled=false \
      --set pcf.enabled=false \
      --set scp.enabled=false \
      --set udm.enabled=false \
      --set udr.enabled=false \
      --set webui.enabled=false \
      --set mongodb.enabled=true \
      --set mongodb.image.tag=4.4.15 \
      --set mongodb.livenessProbe.timeoutSeconds=30 \
      --set mongodb.readinessProbe.timeoutSeconds=30
    ```

3.  **Add Home Subscriber:**
    *   Created `add-subscriber-job.yaml` to run `open5gs-dbctl`.
        ```yaml
        # add-subscriber-job.yaml
        apiVersion: batch/v1
        kind: Job
        metadata:
          name: add-home-subscriber
          namespace: home-network
        spec:
          template:
            spec:
              containers:
              - name: dbctl
                image: docker.io/gradiant/open5gs-dbctl:0.10.3
                command: ["open5gs-dbctl", "add_ue_with_slice", "999700000000001", "465B5CE8B199B49FAA5F0A2EE238A6BC", "E8ED289DEBA952E4283B54E88E6183CA", "internet", "1", "ffffff"]
                env:
                - name: DB_URI
                  value: "mongodb://home-open5gs-mongodb/open5gs"
              restartPolicy: Never
          backoffLimit: 4
        ```
    *   Applied the job: `kubectl apply -f add-subscriber-job.yaml`
    *   Verified job completion (`kubectl get job add-home-subscriber -n home-network`).

4.  **Deploy Home Network NFs:**
    *   Installed the remaining Home NFs using Helm release `home-open5gs-nfs`.
    *   Disabled MongoDB deployment (`mongodb.enabled=false`).
    *   Explicitly set `dbURI=mongodb://home-open5gs-mongodb/open5gs` for the release.
    *   Set `DB_URI` environment variable override for UDR, PCF, and WebUI components.
    *   Disabled WebUI populate init container (`webui.populate.enabled=false`).
    *   Disabled SMF Diameter/PCRF interaction (`smf.config.pcrf.enabled=false`).
    ```bash
    helm install home-open5gs-nfs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.0 \
      --namespace home-network \
      --set dbURI=mongodb://home-open5gs-mongodb/open5gs \
      --set udr.extraEnvVars[0].name=DB_URI \
      --set udr.extraEnvVars[0].value=mongodb://home-open5gs-mongodb/open5gs \
      --set pcf.extraEnvVars[0].name=DB_URI \
      --set pcf.extraEnvVars[0].value=mongodb://home-open5gs-mongodb/open5gs \
      --set webui.extraEnvVars[0].name=DB_URI \
      --set webui.extraEnvVars[0].value=mongodb://home-open5gs-mongodb/open5gs \
      --set webui.populate.enabled=false \
      --set populate.enabled=false \
      --set hss.enabled=false \
      --set mme.enabled=false \
      --set pcrf.enabled=false \
      --set sgwc.enabled=false \
      --set sgwu.enabled=false \
      --set amf.enabled=true \
      --set smf.enabled=true \
      --set upf.enabled=true \
      --set ausf.enabled=true \
      --set bsf.enabled=true \
      --set nrf.enabled=true \
      --set nssf.enabled=true \
      --set pcf.enabled=true \
      --set scp.enabled=true \
      --set udm.enabled=true \
      --set udr.enabled=true \
      --set webui.enabled=true \
      --set mongodb.enabled=false \
      --set smf.config.pcrf.enabled=false
    ```

5.  **Deploy Visited Network Core:**
    *   Installed the full Visited network core using Helm release `visited-open5gs`.
    *   Used MongoDB image `4.4.15`.
    *   Increased MongoDB probe timeouts.
    *   Set `DB_URI` environment variable override for UDR, PCF, and WebUI components.
    *   Disabled WebUI populate init container.
    *   Disabled SMF Diameter/PCRF interaction.
    ```bash
    helm install visited-open5gs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.0 \
      --namespace visited-network \
      --set mongodb.image.tag=4.4.15 \
      --set smf.config.pcrf.enabled=false \
      --set mongodb.livenessProbe.timeoutSeconds=30 \
      --set mongodb.readinessProbe.timeoutSeconds=30 \
      --set udr.extraEnvVars[0].name=DB_URI \
      --set udr.extraEnvVars[0].value=mongodb://visited-open5gs-mongodb/open5gs \
      --set pcf.extraEnvVars[0].name=DB_URI \
      --set pcf.extraEnvVars[0].value=mongodb://visited-open5gs-mongodb/open5gs \
      --set webui.extraEnvVars[0].name=DB_URI \
      --set webui.extraEnvVars[0].value=mongodb://visited-open5gs-mongodb/open5gs \
      --set webui.populate.enabled=false \
      --set populate.enabled=false \
      --set hss.enabled=false \
      --set mme.enabled=false \
      --set pcrf.enabled=false \
      --set sgwc.enabled=false \
      --set sgwu.enabled=false \
      --set amf.enabled=true \
      --set smf.enabled=true \
      --set upf.enabled=true \
      --set ausf.enabled=true \
      --set bsf.enabled=true \
      --set nrf.enabled=true \
      --set nssf.enabled=true \
      --set pcf.enabled=true \
      --set scp.enabled=true \
      --set udm.enabled=true \
      --set udr.enabled=true \
      --set webui.enabled=true
      # Note: mongodb.enabled defaults to true and was used here
    ```

6.  **Configure SEPPs (Values Files):**
    *   Created `home-sepp-values.yaml`:
        ```yaml
        customOpen5gsConfig:
          global:
            max:
              ue: 1024
          sepp:
            sbi:
              server:
                - address: 0.0.0.0
                  port: 7777
              client:
                nrf:
                  - uri: http://home-open5gs-nfs-nrf-sbi.home-network.svc.cluster.local:7777
            n32:
              server:
                - sender: home-sepp.home-network.svc.cluster.local
                  scheme: http
                  address: 0.0.0.0
                  port: 7443
              n32f:
                scheme: http
                address: 0.0.0.0
              client:
                sepp:
                  - receiver: visited-sepp.visited-network.svc.cluster.local
                    # uri initially set to internal name, later updated in step 8
                    uri: http://<INITIAL_INTERNAL_URI_PLACEHOLDER> 
                    plmn_id:
                      mcc: "001"
                      mnc: "01"
            default: {}
        ```
    *   Created `visited-sepp-values.yaml`:
        ```yaml
        customOpen5gsConfig:
          global:
            max:
              ue: 1024
          sepp:
            sbi:
              server:
                - address: 0.0.0.0
                  port: 7777
              client:
                nrf:
                  - uri: http://visited-open5gs-nrf-sbi.visited-network.svc.cluster.local:7777
            n32:
              server:
                - sender: visited-sepp.visited-network.svc.cluster.local
                  scheme: http
                  address: 0.0.0.0
                  port: 7443
              n32f:
                scheme: http
                address: 0.0.0.0
              client:
                sepp:
                  - receiver: home-sepp.home-network.svc.cluster.local
                    # uri initially set to internal name, later updated in step 8
                    uri: http://<INITIAL_INTERNAL_URI_PLACEHOLDER> 
                    plmn_id:
                      mcc: "999"
                      mnc: "70"
            default: {}
        ```

7.  **Initial SEPP Deployment (Local Chart):**
    ```bash
    helm uninstall home-sepp -n home-network && helm install home-sepp ./charts/open5gs-sepp -f home-sepp-values.yaml --namespace home-network && \
    helm uninstall visited-sepp -n visited-network && helm install visited-sepp ./charts/open5gs-sepp -f visited-sepp-values.yaml --namespace visited-network
    ```
    *(Note: This deployment failed due to various configuration errors fixed iteratively)*

8.  **Expose SEPP N32 Interfaces:**
    *   Identified SEPP N32 services (`home-sepp-open5gs-sepp-n32`, `visited-sepp-open5gs-sepp-n32`).
    *   Patched services to `type: LoadBalancer`:
        ```bash
        kubectl patch service home-sepp-open5gs-sepp-n32 -n home-network -p '{"spec": {"type": "LoadBalancer"}}'
        kubectl patch service visited-sepp-open5gs-sepp-n32 -n visited-network -p '{"spec": {"type": "LoadBalancer"}}'
        ```
    *   Waited for external IP/NodePort assignment (required `minikube tunnel`).
    *   Retrieved Minikube IP (`minikube ip` -> `192.168.58.2`) and NodePorts (`kubectl get svc ...` -> Home: `31704`, Visited: `30526`). *(Note: These ports might change on subsequent runs)*.

9.  **Reconfigure SEPPs for External Communication:**
    *   Updated `n32.client.sepp.uri` in `home-sepp-values.yaml` to `http://192.168.58.2:30526`.
    *   Updated `n32.client.sepp.uri` in `visited-sepp-values.yaml` to `http://192.168.58.2:31704`.
    *   Reinstalled both SEPPs with updated values files:
        ```bash
        helm uninstall home-sepp -n home-network
        helm install home-sepp ./charts/open5gs-sepp -f home-sepp-values.yaml --namespace home-network
        helm uninstall visited-sepp -n visited-network
        helm install visited-sepp ./charts/open5gs-sepp -f visited-sepp-values.yaml --namespace visited-network
        ```
    ***Note on Changing IPs:*** If the Minikube IP address or the NodePorts assigned to the SEPP N32 LoadBalancer services change (e.g., after a Minikube restart or service recreation), you must:
    1.  Re-run `minikube ip` and `kubectl get svc ... -n <namespace>` to get the new IP and NodePorts.
    2.  Update the `uri:` fields in `home-sepp-values.yaml` and `visited-sepp-values.yaml` with the new values.
    3.  Repeat the `helm uninstall` and `helm install` commands above for both SEPPs to apply the changes.

10. **Deploy PacketRusher:**
    *   Created `packetrusher-values.yaml`:
        ```yaml
        config:
          amf:
            hostname: visited-open5gs-amf-ngap.visited-network.svc.cluster.local
          gnb:
            mcc: "001"
            mnc: "01"
            tac: "000001" # 3-byte hex representation
            gnbid: "000008" 
            sst: "1"      
            sd: "ffffff" 
          ue:
            msin: "0000000001"
            key: "465B5CE8B199B49FAA5F0A2EE238A6BC"
            opc: "E8ED289DEBA952E4283B54E88E6183CA"
            dnn: "internet"
            hplmn:
              mcc: "999"
              mnc: "70"
            sst: "1"
            sd: "ffffff"
        ```
    *   Installed using local chart:
        ```bash
        helm install packetrusher ./charts/packetrusher -f packetrusher-values.yaml --namespace visited-network
        ```

**Final Status:**
*   Home Network Core: Healthy (except WebUI init container).
*   Visited Network Core: Healthy.
*   Home SEPP: Healthy, N32 exposed via NodePort.
*   Visited SEPP: Healthy, N32 exposed via NodePort, successfully connected to Home SEPP N32.
*   PacketRusher: Deployed but crashing (panic during PDU session establishment, likely internal bug or incompatibility).

---

## MME Configuration and Troubleshooting Notes

The **MME (Mobility Management Entity)** is a key control-plane node in the 4G EPC (Evolved Packet Core). It handles UE tracking, connection management, authentication, and session management coordination.

**In this 5G Roaming Deployment:**

*   We focused on 5G Network Functions (AMF, SMF, etc.).
*   The MME was explicitly **disabled** in both the home and visited core network deployments (`--set mme.enabled=false`).
*   Therefore, MME configuration and logs were not directly relevant to the issues encountered during this specific setup.

**General MME Configuration (if it were enabled):**

If you were deploying a 4G EPC or a 4G/5G combo core *with* MME enabled, you would configure it via its `mme.yaml` file or corresponding Helm chart values (`open5gs.mme.*` or similar). Key parameters include:

*   **`mme.gummei`:** Defines the MME's identity within the PLMN.
    *   `plmn_id`: MCC and MNC of the network.
    *   `mme_gid`: MME Group ID.
    *   `mme_code`: MME Code within the group.
*   **`mme.tai_list`:** Lists the Tracking Area Identities (TACs) served by this MME. Each TAI includes MCC, MNC, and TAC. eNodeBs must be configured with a TAC belonging to this list to connect.
*   **`mme.s1ap`:** Binds the MME's S1AP interface (for communication with eNodeBs) to a specific network device or IP address.
*   **`mme.gtpc`:** Binds the MME's S11 interface (GTP-C for communication with SGW-C) to a specific network device or IP address.
*   **`mme.network_name`:** Configures the network name broadcast to UEs.
*   **`mme.security`:** Defines the preferred order for security algorithms (integrity and ciphering).
*   **`mme.diameter`:** Configures the Diameter connection parameters (local endpoints, realm) for connecting to the HSS (Home Subscriber Server) over the S6a interface.
*   **Connections to SGW-C:** Specifies the address(es) of the Serving Gateway Control Plane Function(s).
*   **Connections to SMF/PGW-C:** (If interfacing with 5G SMF or 4G PGW-C) Specifies addresses for session management.

**Troubleshooting MME:**

*   **Check Logs:** The primary tool is the MME log file (usually `/var/log/open5gs/mme.log` or retrieved via `kubectl logs <mme-pod>`).
*   **eNodeB Connection Issues:** Look for S1AP errors in the log. Common issues include:
    *   `connection refused`: MME service not running or listening on the correct IP/port.
    *   `unknown eNB`: eNodeB's PLMN ID or TAC doesn't match MME configuration.
    *   Firewall blocking SCTP traffic (port 36412).
*   **SGW-C Connection Issues:** Look for GTP-C errors. Ensure the configured SGW-C address is reachable and the SGW-C is running.
*   **HSS Connection Issues:** Look for Diameter errors. Ensure the HSS address/realm is correct, HSS is running, and Diameter routes are established. Error `Result-Code:3002` (DIAMETER_UNABLE_TO_DELIVER) often means the HSS is unreachable or down.
*   **UE Attach/Registration Failures:**
    *   Authentication failures (check HSS logs, SIM credentials vs. DB credentials).
    *   Session creation failures (check SGW-C and potentially SMF/PGW-C logs).

---

**Next Steps / Outstanding Issues:**
*   Resolve PacketRusher crash (requires debugging PacketRusher, trying a different version, or using an alternative UE simulator).
*   (Optional) Fix Home WebUI init container failure (likely requires modifying the `open5gs-webui` sub-chart template directly).
*   Perform actual roaming tests once a working UE simulator is available. 