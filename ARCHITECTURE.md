# Architecture Deep Dive

## Security Model: VPN Endpoint Isolation

### The Challenge

The requirement is to have `/secure-status` only accessible via VPN while `/status` is publicly accessible. This creates an interesting architecture challenge.

### Solution: Dual-Service Architecture

We deploy **two separate ECS services** from the **same container image**, differentiated by the `API_MODE` environment variable:

#### Public Service
- **Location**: Public subnets behind Application Load Balancer
- **Environment**: `API_MODE=public`
- **Accessible Endpoints**:
  - ✅ `/status` - Returns incremented counter + random number
  - ✅ `/metrics` - Returns time-series data for `/status` only
  - ❌ `/secure-status` - Returns 404 (application-level filtering)
- **Security Groups**: ALB allows 80/443 from internet, ECS tasks allow port 5000 from ALB only

#### Private Service
- **Location**: Private subnets with Service Discovery DNS
- **Environment**: `API_MODE=private`
- **Accessible Endpoints**:
  - ❌ `/status` - Returns 404 (application-level filtering)
  - ✅ `/secure-status` - Returns incremented counter + random number
  - ✅ `/metrics` - Returns time-series data for `/secure-status` only
- **Security Groups**: Only allows port 5000 from VPN CIDR (10.0.100.0/24)
- **DNS**: `private-api.seasats.local` resolves to private ECS service IP

### Application-Level Enforcement

The Flask application checks the `API_MODE` environment variable:

```python
@app.route('/status', methods=['GET'])
def status():
    if API_MODE != 'public':
        return jsonify({'error': 'Not found'}), 404
    # ... rest of implementation

@app.route('/secure-status', methods=['GET'])
def secure_status():
    if API_MODE != 'private':
        return jsonify({'error': 'Not found'}), 404
    # ... rest of implementation
```

This ensures that:
1. The public API service will return 404 for `/secure-status` requests
2. The private API service will return 404 for `/status` requests

### Network-Level Enforcement

Even if someone bypassed application logic, the network security provides defense in depth:

1. **Private API is not publicly routable**
   - Lives in private subnets with no public IP
   - No route from internet to private subnets
   - Only accessible from within VPC

2. **Security Group Restrictions**
   - Private API security group: Allows port 5000 from 10.0.100.0/24 ONLY
   - VPN clients get IPs in 10.0.100.0/24 range
   - Without VPN, your IP is not in allowed range

3. **VPN Tunnel**
   - WireGuard assigns client IP in VPC CIDR (10.0.100.2)
   - Routes traffic for 10.0.0.0/16 through VPN tunnel
   - VPN server forwards to private subnets
   - DNS resolution for `private-api.seasats.local` happens via VPC DNS

## Data Flow

### Public Endpoint Access

```
Client
  │
  └─► ALB (public-facing)
        │
        └─► Public ECS Service (10.0.0.x)
              │
              ├─► /status ──► DynamoDB (endpoint="status")
              └─► /metrics ──► DynamoDB (query endpoint="status", return data)
```

### Secure Endpoint Access (VPN Required)

```
Client
  │
  └─► WireGuard VPN (encrypted tunnel)
        │
        └─► VPN Server (10.0.100.1)
              │
              └─► Private ECS Service (10.0.10.x)
                    │
                    ├─► /secure-status ──► DynamoDB (endpoint="secure-status")
                    └─► /metrics ──► DynamoDB (query endpoint="secure-status", return data)
```

### Frontend Dashboard Access

```
Browser
  │
  ├─► CloudFront ──► S3 (static HTML/JS)
  │
  ├─► Public ALB ──► /metrics (gets status data)
  │
  └─► [If VPN connected]
        └─► Private API ──► /metrics (gets secure-status data)
```

The frontend attempts to fetch from both endpoints:
- Public API always works (returns `/status` metrics)
- Private API only works when VPN connected (returns `/secure-status` metrics)
- Charts display combined data

## Why This Approach?

### Alternative Approaches Considered

#### 1. Single Service with IP-Based Filtering
**Rejected**: Application-level IP filtering is less secure and more complex than infrastructure-based security.

#### 2. API Gateway with Custom Authorizer
**Rejected**: Overkill for POC, adds complexity and cost.

#### 3. VPN directly to ECS tasks
**Rejected**: ECS Fargate tasks don't have persistent IPs, would need NLB which is more expensive.

### Benefits of Chosen Approach

1. **Defense in Depth**: Two layers of security (network + application)
2. **Clean Separation**: Each service has single responsibility
3. **Infrastructure-Enforced**: Security groups prevent unauthorized access
4. **Simple Deployment**: Same container image, different environment variable
5. **Testable**: Can independently verify each service works correctly
6. **Maintainable**: Clear separation of concerns

## DynamoDB Schema

### Time-Series Approach

```
Table: api-metrics
PK: endpoint (STRING)    SK: timestamp (NUMBER)    Attributes
─────────────────────────────────────────────────────────────
"status"                 1702566000                 count: 1
"status"                 1702566015                 count: 2
"status"                 1702566030                 count: 3
"secure-status"          1702566000                 count: 1
"secure-status"          1702566045                 count: 2
```

### Operations

**Write (on each hit)**:
1. Query latest record for endpoint (descending by timestamp, limit 1)
2. Increment count
3. Write new record with current timestamp

**Read (for API response)**:
1. Query latest record for endpoint
2. Return count + random number

**Read (for metrics visualization)**:
1. Query partition with timestamp >= (now - 24h)
2. Return all records in time range

### Trade-offs

**Pros**:
- Simple schema
- Automatic history
- Easy time-range queries
- No separate counter management

**Cons**:
- Read before write (latency)
- Race condition risk (documented in improvements)
- Storage grows over time (needs TTL or cleanup)

**Production Fix**:
Use DynamoDB atomic counters with UpdateItem and separate time-series population:
- Counter table: `{endpoint: "status", count: 42}`
- Time-series table: Same as current
- DynamoDB Streams to populate time-series from counter updates

## VPN Architecture

### WireGuard Configuration

**Server** (EC2 in public subnet):
- Interface: `wg0` at `10.0.100.1/24`
- Listens on UDP port 51820
- Routes traffic for VPC CIDR (10.0.0.0/16)
- NAT/masquerade enabled for VPC access

**Client**:
- Gets IP `10.0.100.2/24`
- Routes VPC CIDR through tunnel
- Uses VPC DNS (10.0.0.2)
- Persistent keepalive every 25 seconds

### Traffic Flow

1. Client connects to VPN server public IP
2. WireGuard establishes encrypted tunnel
3. Client gets IP 10.0.100.2
4. DNS queries for `private-api.seasats.local` go to VPC DNS
5. VPC DNS returns private ECS task IP (10.0.10.x)
6. Traffic routes through VPN tunnel to VPN server
7. VPN server forwards to VPC (10.0.10.x)
8. Private API security group accepts traffic from 10.0.100.2

### Security Properties

- **Encryption**: ChaCha20-Poly1305 for tunnel encryption
- **Authentication**: Public/private key pairs (no passwords)
- **Firewall**: Only VPN CIDR allowed to access private API
- **Isolation**: VPN clients can only access private API, not other VPC resources

## Cost Optimization

Estimated monthly costs (us-east-1):

- **ECS Fargate**: ~$15/month (2 tasks, 0.25 vCPU, 0.5GB each)
- **ALB**: ~$20/month
- **NAT Gateway**: ~$35/month (can be shared)
- **VPN Server (t3.micro)**: ~$8/month
- **DynamoDB**: ~$1/month (on-demand, low traffic)
- **S3 + CloudFront**: ~$1/month
- **Data Transfer**: Variable, ~$5/month for testing

**Total**: ~$85/month

**Cost Reduction Options**:
- Use Spot instances for VPN server (-70%)
- Remove NAT Gateway if private service doesn't need internet (-$35)
- Use single AZ for testing (-50% networking)

## Production Considerations

For production deployment, consider:

1. **High Availability**:
   - Multi-AZ NAT Gateways
   - Auto-scaling for ECS services
   - Multiple VPN servers with failover

2. **Monitoring**:
   - CloudWatch alarms for service health
   - VPN connection monitoring
   - DynamoDB throttling alerts

3. **Security**:
   - WAF on ALB
   - VPC Flow Logs
   - GuardDuty for threat detection
   - Secrets Manager for sensitive config

4. **Performance**:
   - DynamoDB provisioned capacity or on-demand auto-scaling
   - ElastiCache for frequently accessed data
   - CloudFront for API caching

5. **Compliance**:
   - Encryption at rest for DynamoDB
   - S3 bucket encryption
   - VPC endpoint for AWS services
   - Audit logging with CloudTrail
