# Open5GS 5G Roaming Setup with SEPP, Home and Visited Networks

This setup demonstrates a 5G roaming scenario using Open5GS and PacketRusher. It creates:

1. A **Home Network** with Open5GS core components and SEPP
2. A **Visited Network** with Open5GS core components and SEPP
3. A simulated UE using **PacketRusher** that connects through the visited network while having its subscription in the home network

## Architecture

```
┌───────────────────────┐                       ┌───────────────────────┐
│                       │                       │                       │
│    HOME NETWORK       │                       │   VISITED NETWORK     │
│    (PLMN: 999-70)     │                       │   (PLMN: 001-01)      │
│                       │                       │                       │
│  ┌─────────────────┐  │                       │  ┌─────────────────┐  │
│  │                 │  │  N32 Interface        │  │                 │  │
│  │  5G Core        │  │                       │  │  5G Core        │  │
│  │  Components     │◄─┼───────────────────────┼──┤  Components     │  │
│  │  (AMF,UDM,etc)  │  │  (SEPP-to-SEPP)       │  │  (AMF,UDM,etc)  │  │
│  │                 │  │                       │  │                 │  │
│  └────────┬────────┘  │                       │  └────────┬────────┘  │
│           │           │                       │           │           │
│  ┌────────▼────────┐  │                       │  ┌────────▼────────┐  │
│  │                 │  │                       │  │                 │  │
│  │  SEPP           │◄─┼───────────────────────┼──┤  SEPP           │  │
│  │                 │  │                       │  │                 │  │
│  └─────────────────┘  │                       │  └─────────────────┘  │
│                       │                       │           ▲           │
└───────────────────────┘                       │           │           │
                                                │  ┌────────▼────────┐  │
                                                │  │                 │  │
                                                │  │  PacketRusher   │  │
                                                │  │  (UE+gNB)       │  │
                                                │  │                 │  │
                                                │  └─────────────────┘  │
                                                │                       │
                                                └───────────────────────┘
```

In this scenario:
- UE's subscription data is stored in the Home Network
- UE connects to a gNB in the Visited Network
- Authentication and authorization happens via N32 SEPP-to-SEPP interface
- Data communications are handled by the Visited Network

## Prerequisites

- Kubernetes cluster (Minikube or any other Kubernetes implementation)
- Helm 3
- kubectl

## Setup Instructions

1. **Clone the repository**:
   ```
   git clone https://github.com/your-repo/5g-charts.git
   cd 5g-charts
   ```

2. **Create the necessary namespaces**:
   ```
   kubectl create namespace home-network
   kubectl create namespace visited-network
   ```

3. **Deploy the entire setup**:
   ```
   ./deploy-roaming.sh
   ```

4. **Monitor the deployment**:
   ```
   kubectl get pods -n home-network
   kubectl get pods -n visited-network
   ```

5. **Check roaming connectivity**:
   ```
   kubectl logs -f -n visited-network deployment/packetrusher
   ```

6. **Access the Open5GS WebUI**:
   ```
   # Forward port for Home Network WebUI
   kubectl port-forward -n home-network svc/home-network-open5gs-webui 3000:3000
   
   # Forward port for Visited Network WebUI
   kubectl port-forward -n visited-network svc/visited-network-open5gs-webui 3001:3000
   ```
   
   Then access:
   - Home Network WebUI: http://localhost:3000 (default credentials: admin/1423)
   - Visited Network WebUI: http://localhost:3001 (default credentials: admin/1423)

7. **Clean up when finished**:
   ```
   ./cleanup-roaming.sh
   ```

## Configuration Details

### Home Network

- PLMN: 999-70
- SEPP configured to initiate N32 connection to Visited Network SEPP
- Subscriber IMSI: 999700000000001 with international roaming enabled

### Visited Network

- PLMN: 001-01
- SEPP configured to accept N32 connection from Home Network SEPP
- Configured to support Home Network PLMN for roaming

### PacketRusher UE

- Connects to Visited Network AMF
- Uses subscription from Home Network
- Configured with Home PLMN identifiers
- Attempts to establish PDU session through visited network

## Troubleshooting

- **SEPP Connectivity Issues**: Check logs of both SEPPs for connection errors
  ```
  kubectl logs -n home-network deployment/home-sepp
  kubectl logs -n visited-network deployment/visited-sepp
  ```

- **UE Registration Failure**: Check AMF logs in visited network
  ```
  kubectl logs -n visited-network deployment/visited-network-open5gs-amf
  ```

- **Authentication Issues**: Check UDM/AUSF logs in home network
  ```
  kubectl logs -n home-network deployment/home-network-open5gs-udm
  kubectl logs -n home-network deployment/home-network-open5gs-ausf
  ```

## References

- [Open5GS Documentation](https://open5gs.org/open5gs/docs/)
- [3GPP TS 23.501 - Roaming Architecture](https://www.3gpp.org/DynaReport/23501.htm)
- [PacketRusher Documentation](https://github.com/PacketRusher/packetrusher)

## License

This project is licensed under the same terms as the original 5g-charts repository.

## Additional Instructions

To deploy the visiting network:
```
./deploy-visited-network.sh
```