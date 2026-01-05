# Retail Store Sample Application - Features

The sample application offers several features outside of its functionality a retail store.

### Theming

The primary color of the UI can be changed via configuration values, which is useful to provide a distinct appearance.

This is the default theme:

![Default theme](./images/theme-default.png)

This is an alternative theme:

![Alternative theme](./images/theme-orange.png)

The theme can be changed in two ways:

1. Set the `RETAIL_UI_THEME` environment variable
2. Append `?theme=<name>` to any URL in the UI. This will set a cookie that persists the theme between page reloads.

See the [UI component configuration section](../src/ui#configuration) for valid values for the theme.

### Introspection information

This is a page in the UI component that displays information about the environment the container is deployed in. This is useful for demonstrations where it is necessary to show aspects such as cross-AZ load balancing and many others.

The implementation includes metadata for Kubernetes, Amazon EC2, Amazon ECS and AWS Lambda.

This example shows a container running in Amazon ECS:

![Metadata page](./images/metadata.png)

The page can be found at `/info`.

To highlight specific attributes you add their names to the URL. For example `/info?attr=ecs.cloud.region,ecs.cloud.availability_zone,ecs.cloud.account.id`:

![Metadata page attributes](./images/metadata-attr.png)

You can find the attribute IDs by hovering your cursor over the relevant attribute name in the table:

![Metadata page attribute ID](./images/metadata-attr-id.png)

### Application topology

This is a page in the UI component that displays information about the application topology thats been deployed. For example it shows what components are deployed, their health and information about their configured dependencies like databases.

![Metadata page attributes](./images/topology.png)

The page can be found at `/topology`.

### Network Flow Monitoring Setup

The EKS cluster includes the Network Flow Monitoring Agent addon which provides container network observability. While the agent is automatically deployed via Terraform, you need to manually create a **Scope** and **Monitor** to start collecting and visualizing network flow data.

#### Prerequisites

- EKS cluster deployed with the `aws-network-flow-monitoring-agent` addon
- AWS CLI configured with appropriate permissions
- kubectl configured to access your cluster

#### Step 1: Verify the Network Flow Monitoring Agent is Running

```bash
# Check if the addon is installed
aws eks describe-addon \
  --cluster-name retail-store \
  --addon-name aws-network-flow-monitoring-agent \
  --query 'addon.status'

# Verify the agent pods are running
kubectl get pods -n amazon-network-flow-monitor
```

You should see pods with status `Running`.

#### Step 2: Create a Network Flow Monitor Scope

A scope defines which resources to monitor. Create a scope for your EKS cluster:

```bash
# Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
CLUSTER_NAME="retail-store"

# Create a scope targeting your EKS cluster
aws networkflowmonitor create-scope \
  --scope-name "${CLUSTER_NAME}-scope" \
  --targets "targetIdentifier={targetId={accountId=${ACCOUNT_ID}},targetType=ACCOUNT},region=${REGION}"
```

#### Step 3: Create a Network Flow Monitor

Create a monitor that uses the scope to collect flow data:

```bash
# Get the scope ARN from the previous step
SCOPE_ARN=$(aws networkflowmonitor list-scopes \
  --query "scopes[?scopeName=='${CLUSTER_NAME}-scope'].scopeArn" \
  --output text)

# Create the monitor
aws networkflowmonitor create-monitor \
  --monitor-name "${CLUSTER_NAME}-monitor" \
  --scope-arn "${SCOPE_ARN}" \
  --local-resources "type=AWS::EKS::Cluster,identifier=arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"
```

#### Step 4: View Network Flow Data in the Console

1. Open the [Amazon CloudWatch Console](https://console.aws.amazon.com/cloudwatch)
2. In the left navigation, click **Network Monitoring** → **Network Flow Monitor**
3. Select your monitor (`retail-store-monitor`)
4. Explore the following views:
   - **Service Map**: Visual representation of service-to-service traffic
   - **Flow Table**: Detailed network flow records between pods
   - **Performance Metrics**: Latency, packet loss, and throughput metrics

#### Step 5: View in EKS Console (Alternative)

1. Open the [Amazon EKS Console](https://console.aws.amazon.com/eks)
2. Select your cluster (`retail-store`)
3. Navigate to the **Observability** tab
4. Click on **Network Flow Monitor** to see:
   - Traffic flows between services
   - Network latency metrics
   - Connection statistics

#### Useful CLI Commands

```bash
# List all scopes
aws networkflowmonitor list-scopes

# List all monitors
aws networkflowmonitor list-monitors

# Get monitor status
aws networkflowmonitor get-monitor --monitor-name "${CLUSTER_NAME}-monitor"

# Query top contributors (traffic sources)
aws networkflowmonitor start-query-workload-insights-top-contributors \
  --scope-name "${CLUSTER_NAME}-scope" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --metric-name ROUND_TRIP_TIME \
  --destination-category INTER_AZ
```

#### Cleanup

To remove the Network Flow Monitor resources:

```bash
# Delete the monitor first
aws networkflowmonitor delete-monitor --monitor-name "${CLUSTER_NAME}-monitor"

# Then delete the scope
aws networkflowmonitor delete-scope --scope-name "${CLUSTER_NAME}-scope"
```

> **Note:** The Network Flow Monitoring Agent addon will continue running and can be reused with new scopes/monitors. To fully disable network flow monitoring, remove the addon via Terraform or the EKS console.

---

### Generative AI chat bot

This feature provides a chat bot interface directly in the store UI which can be used to demonstrate basic LLM inference use-cases. It is works with Amazon Bedrock and OpenAI compatible endpoints via configuration properties.

![Chat bot UI](./images/chat-bot.png)

The chat bot is disabled by default, and can be enabled by setting the environment variable `RETAIL_UI_CHAT_ENABLED=true`. This will enable the following button to display on the botton-right area of the UI:

![Chat bot button](./images/chat-bot-button.png)

You must also configure one of the below providers.

See the [UI component configuration section](../src/ui#configuration) for more options.

#### Mock provider

This is designed for quick testing and can be enabled by setting `RETAIL_UI_CHAT_PROVIDER=mock`. It will return a hard-coded response.

#### Amazon Bedrock

This provides integration with Amazon Bedrock, the example below shows the relevant configuration values as environment variables:

```bash
RETAIL_UI_CHAT_PROVIDER=bedrock # Use Amazon Bedrock
RETAIL_UI_CHAT_MODEL=anthropic.claude-3-5-sonnet-20241022-v2:0 # Provide Bedrock model ID
RETAIL_UI_CHAT_BEDROCK_REGION=us-west-2 # Configure the region to use for Bedrock API calls
```

#### OpenAI endpoint

This provides integration with any OpenAI-compatible endpoint, the example below shows the relevant configuration values as environment variables:

```bash
RETAIL_UI_CHAT_PROVIDER=openai # Use an OpenAPI compatible endpoint
RETAIL_UI_CHAT_MODEL=meta-llama/Meta-Llama-3.1-8B # Provide a model ID
RETAIL_UI_CHAT_OPENAI_BASE_URL=http://localhost:8000 # (Optional) Base URL for the OpenAI API, usually for self-hosted LLMs
RETAIL_UI_CHAT_OPENAI_API_KEY=<YOUR API KEY> # (Optional) API key for the OpenAPI endpoint
```
