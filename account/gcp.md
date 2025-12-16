# GCP Using Foundry
#### Environment Setup
> Set the following variables in your `.env` file:
```ts
GCP_PROJECT_ID=""
GCP_LOCATION=""
GCP_KEY_RING=""
GCP_KEY_NAME=""
GCP_KEY_VERSION=""
GOOGLE_APPLICATION_CREDENTIALS=`absolute path of .json file`
```

Execute Foundry scripts with GCP integration:
```
forge script <script_path>  --rpc-url <rpc_url> --gcp --broadcast
```

**Parameters:**
- `<script_path>`: Path to your Foundry script
- `<rpc_url>`: RPC endpoint URL for the target network
- `--gcp`: Enable Google Cloud Platform key management
- `--broadcast`: Broadcast transactions to the network

source: https://getfoundry.sh/forge/reference/script#forge-script