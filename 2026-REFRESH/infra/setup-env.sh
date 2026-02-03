#!/bin/bash
# =============================================================================
# Azure AI Red Teaming Labs - Environment Setup Script (2026 Refresh)
# =============================================================================
# This script automatically configures your .env file by detecting Azure 
# resources in your subscription and prompting for selections when needed.
#
# Usage:
#   ./infra/setup-env.sh
#
# Requirements:
#   - Azure CLI installed and logged in (az login)
#   - Access to Azure subscription with Foundry resources
# =============================================================================

set -e  # Exit on error

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFRESH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$REFRESH_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
ENV_SAMPLE="$SCRIPT_DIR/.env.sample"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "========================================================================="
echo "  🔧 Azure AI Red Teaming Labs - Environment Setup (2026)"
echo "========================================================================="
echo ""

# =============================================================================
# Step 1: Check Prerequisites
# =============================================================================
echo -e "${BLUE}[1/9] Checking prerequisites...${NC}"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI not found. Please install it first:${NC}"
    echo "   https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
echo "✓ Azure CLI installed"

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}⚠  Not logged in to Azure. Running 'az login'...${NC}"
    az login
fi
echo "✓ Logged into Azure CLI"
echo ""

# =============================================================================
# Step 2: Create .env file from template
# =============================================================================
echo -e "${BLUE}[2/9] Setting up .env file...${NC}"

if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}⚠  .env file already exists${NC}"
    read -p "Overwrite existing .env? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing .env and updating values..."
    else
        cp "$ENV_SAMPLE" "$ENV_FILE"
        echo "✓ Created new .env from template"
    fi
else
    if [ ! -f "$ENV_SAMPLE" ]; then
        echo -e "${RED}❌ Template file not found: $ENV_SAMPLE${NC}"
        exit 1
    fi
    cp "$ENV_SAMPLE" "$ENV_FILE"
    echo "✓ Created .env file from template"
fi
echo ""

# =============================================================================
# Step 3: Get Azure Subscription
# =============================================================================
echo -e "${BLUE}[3/9] Getting Azure subscription...${NC}"

SELECTED_SUB=$(az account show --query "id" -o tsv)
SELECTED_SUB_NAME=$(az account show --query "name" -o tsv)
echo "✓ Using subscription: $SELECTED_SUB_NAME"
echo "  ID: $SELECTED_SUB"
echo ""

# =============================================================================
# Step 4: Find and select Resource Group
# =============================================================================
echo -e "${BLUE}[4/9] Searching for resource groups...${NC}"

ALL_RGS=($(az group list --query "[].name" -o tsv))

# Find resource groups containing "Lab516" or "LAB516" (case-insensitive)
LAB516_RGS=()
for rg in "${ALL_RGS[@]}"; do
    if [[ "${rg,,}" == *lab516* ]]; then
        LAB516_RGS+=("$rg")
    fi
done

if [ ${#LAB516_RGS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠  No 'Lab516' resource groups found${NC}"
    echo ""
    echo "Available Resource Groups:"
    select SELECTED_RG in "${ALL_RGS[@]}"; do
        if [ -n "$SELECTED_RG" ]; then
            break
        fi
    done
elif [ ${#LAB516_RGS[@]} -eq 1 ]; then
    SELECTED_RG="${LAB516_RGS[0]}"
    echo "✓ Found resource group: $SELECTED_RG"
else
    echo "Found ${#LAB516_RGS[@]} 'Lab516' resource groups:"
    select SELECTED_RG in "${LAB516_RGS[@]}"; do
        if [ -n "$SELECTED_RG" ]; then
            break
        fi
    done
    echo "✓ Selected: $SELECTED_RG"
fi

# Get resource group location
LOCATION=$(az group show --name "$SELECTED_RG" --query location -o tsv)
echo "✓ Location: $LOCATION"
echo ""

# =============================================================================
# Step 5: Find AI Foundry Resource (AI Services)
# =============================================================================
echo -e "${BLUE}[5/9] Searching for Azure AI Foundry resources...${NC}"

AI_RESOURCES=($(az cognitiveservices account list \
    --resource-group "$SELECTED_RG" \
    --query "[?kind=='AIServices'].name" \
    -o tsv))

if [ ${#AI_RESOURCES[@]} -eq 0 ]; then
    echo -e "${RED}❌ No AI Services found in resource group '$SELECTED_RG'${NC}"
    echo "Please create an Azure AI Foundry project first:"
    echo "  https://ai.azure.com"
    exit 1
elif [ ${#AI_RESOURCES[@]} -eq 1 ]; then
    SELECTED_RESOURCE="${AI_RESOURCES[0]}"
    echo "✓ Found AI Service: $SELECTED_RESOURCE"
else
    echo "Found ${#AI_RESOURCES[@]} AI Services:"
    select SELECTED_RESOURCE in "${AI_RESOURCES[@]}"; do
        if [ -n "$SELECTED_RESOURCE" ]; then
            break
        fi
    done
    echo "✓ Selected: $SELECTED_RESOURCE"
fi
echo ""

# =============================================================================
# Step 6: Find Foundry Project
# =============================================================================
echo -e "${BLUE}[6/9] Searching for Foundry projects...${NC}"

# List projects as child resources
AI_PROJECTS=($(az resource list \
    --resource-group "$SELECTED_RG" \
    --resource-type "Microsoft.CognitiveServices/accounts/projects" \
    --query "[].name" \
    -o tsv))

# Filter projects belonging to selected resource and extract project name
FILTERED_PROJECTS=()
for project in "${AI_PROJECTS[@]}"; do
    if [[ "$project" == "$SELECTED_RESOURCE/"* ]]; then
        project_name="${project#*/}"
        FILTERED_PROJECTS+=("$project_name")
    fi
done

if [ ${#FILTERED_PROJECTS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠  No projects found under '$SELECTED_RESOURCE'${NC}"
    echo "Using AI Service endpoint instead"
    SELECTED_PROJECT=""
    PROJECT_ENDPOINT=""
elif [ ${#FILTERED_PROJECTS[@]} -eq 1 ]; then
    SELECTED_PROJECT="${FILTERED_PROJECTS[0]}"
    echo "✓ Found project: $SELECTED_PROJECT"
else
    echo "Found ${#FILTERED_PROJECTS[@]} projects:"
    select SELECTED_PROJECT in "${FILTERED_PROJECTS[@]}"; do
        if [ -n "$SELECTED_PROJECT" ]; then
            break
        fi
    done
    echo "✓ Selected: $SELECTED_PROJECT"
fi

# Construct project endpoint
if [ -n "$SELECTED_PROJECT" ]; then
    # Try to get endpoint from resource properties
    PROJECT_ENDPOINT=$(az resource show \
        --resource-group "$SELECTED_RG" \
        --resource-type "Microsoft.CognitiveServices/accounts/projects" \
        --name "$SELECTED_RESOURCE/$SELECTED_PROJECT" \
        --query "properties.endpoints.\"AI Foundry API\"" \
        -o tsv 2>/dev/null || echo "")
    
    # Construct if not found
    if [ -z "$PROJECT_ENDPOINT" ] || [ "$PROJECT_ENDPOINT" = "null" ]; then
        PROJECT_ENDPOINT="https://${SELECTED_RESOURCE}.services.ai.azure.com/api/projects/${SELECTED_PROJECT}"
    fi
    echo "✓ Project endpoint: $PROJECT_ENDPOINT"
else
    PROJECT_ENDPOINT=""
fi
echo ""

# =============================================================================
# Step 7: Find Model Deployments
# =============================================================================
echo -e "${BLUE}[7/9] Searching for model deployments...${NC}"

DEPLOYMENTS=($(az cognitiveservices account deployment list \
    --name "$SELECTED_RESOURCE" \
    --resource-group "$SELECTED_RG" \
    --query "[].name" \
    -o tsv 2>/dev/null || echo ""))

if [ ${#DEPLOYMENTS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠  No model deployments found${NC}"
    echo "Please deploy a model (e.g., GPT-4) in the Foundry portal"
    SELECTED_DEPLOYMENT=""
elif [ ${#DEPLOYMENTS[@]} -eq 1 ]; then
    SELECTED_DEPLOYMENT="${DEPLOYMENTS[0]}"
    echo "✓ Found deployment: $SELECTED_DEPLOYMENT"
else
    echo "Found ${#DEPLOYMENTS[@]} model deployments:"
    select SELECTED_DEPLOYMENT in "${DEPLOYMENTS[@]}"; do
        if [ -n "$SELECTED_DEPLOYMENT" ]; then
            break
        fi
    done
    echo "✓ Selected: $SELECTED_DEPLOYMENT"
fi
echo ""

# =============================================================================
# Step 8: Find or Prompt for Agent Name
# =============================================================================
echo -e "${BLUE}[8/9] Configuring agent name...${NC}"

# For now, use default or prompt
read -p "Enter agent name (default: my-first-agent): " INPUT_AGENT
SELECTED_AGENT="${INPUT_AGENT:-my-first-agent}"
echo "✓ Agent name: $SELECTED_AGENT"
echo ""

# =============================================================================
# Step 9: Get Azure OpenAI credentials for Lab 2
# =============================================================================
echo -e "${BLUE}[9/9] Retrieving Azure OpenAI credentials...${NC}"

# Get OpenAI-format endpoint
MODEL_ENDPOINT="https://${SELECTED_RESOURCE}.openai.azure.com"

# Get API key
MODEL_API_KEY=$(az cognitiveservices account keys list \
    --name "$SELECTED_RESOURCE" \
    --resource-group "$SELECTED_RG" \
    --query "key1" \
    -o tsv 2>/dev/null || echo "")

# Set API version
AZURE_OPENAI_API_VERSION="2024-10-01-preview"

if [ -n "$MODEL_API_KEY" ]; then
    echo "✓ Retrieved OpenAI credentials"
    echo "  Endpoint: $MODEL_ENDPOINT"
    echo "  API Key: ${MODEL_API_KEY:0:8}***"
else
    echo -e "${YELLOW}⚠  Could not retrieve API key${NC}"
    MODEL_API_KEY=""
fi
echo ""

# =============================================================================
# Update .env file with all values
# =============================================================================
echo -e "${GREEN}Updating .env file with detected values...${NC}"

# Function to update or add line in .env
update_env() {
    local key="$1"
    local value="$2"
    local file="$ENV_FILE"
    
    # Escape special characters in value for sed
    local escaped_value=$(echo "$value" | sed 's/[\/&]/\\&/g')
    
    if grep -q "^${key}=" "$file"; then
        # Update existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${key}=.*|${key}=${escaped_value}|" "$file"
        else
            sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$file"
        fi
    else
        # Add new line
        echo "${key}=${value}" >> "$file"
    fi
}

# Update all variables
update_env "AZURE_SUBSCRIPTION_ID" "$SELECTED_SUB"
update_env "AZURE_RESOURCE_GROUP" "$SELECTED_RG"
update_env "AZURE_LOCATION" "$LOCATION"

# Foundry project variables
update_env "AZURE_AI_PROJECT" "$SELECTED_PROJECT"
update_env "PROJECT_ENDPOINT" "$PROJECT_ENDPOINT"
update_env "AZURE_AI_PROJECT_ENDPOINT" "$PROJECT_ENDPOINT"
update_env "AZURE_AI_SERVICE" "$SELECTED_RESOURCE"

# Model and agent configuration
update_env "AZURE_AI_DEPLOYMENT_NAME" "$SELECTED_DEPLOYMENT"
update_env "AZURE_AI_MODEL_DEPLOYMENT_NAME" "$SELECTED_DEPLOYMENT"
update_env "AZURE_AI_AGENT_NAME" "$SELECTED_AGENT"

# Lab 2 - Azure OpenAI Direct API variables
update_env "MODEL_ENDPOINT" "$MODEL_ENDPOINT"
update_env "AZURE_OPENAI_ENDPOINT" "$MODEL_ENDPOINT"
update_env "MODEL_API_KEY" "$MODEL_API_KEY"
update_env "AZURE_OPENAI_API_KEY" "$MODEL_API_KEY"
update_env "MODEL_DEPLOYMENT_NAME" "$SELECTED_DEPLOYMENT"
update_env "AZURE_OPENAI_DEPLOYMENT" "$SELECTED_DEPLOYMENT"
update_env "AZURE_OPENAI_API_VERSION" "$AZURE_OPENAI_API_VERSION"

echo -e "${GREEN}✓ Configuration saved to .env${NC}"
echo "  Location: $ENV_FILE"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "========================================================================="
echo -e "${GREEN}  ✅ Setup Complete!${NC}"
echo "========================================================================="
echo ""
echo "📋 Configuration Summary:"
echo "─────────────────────────────────────────────────────────────────────────"
echo "  Subscription:      $SELECTED_SUB_NAME"
echo "  Resource Group:    $SELECTED_RG"
echo "  Location:          $LOCATION"
echo ""
echo "  AI Service:        $SELECTED_RESOURCE"
echo "  AI Project:        ${SELECTED_PROJECT:-<none>}"
echo "  Project Endpoint:  ${PROJECT_ENDPOINT:-<none>}"
echo ""
echo "  Model Deployment:  ${SELECTED_DEPLOYMENT:-<none>}"
echo "  Agent Name:        $SELECTED_AGENT"
echo ""
echo "  Lab 2 - OpenAI Configuration:"
echo "  ├─ Endpoint:       $MODEL_ENDPOINT"
echo "  ├─ API Version:    $AZURE_OPENAI_API_VERSION"
echo "  └─ Deployment:     $SELECTED_DEPLOYMENT"
echo "─────────────────────────────────────────────────────────────────────────"
echo ""
echo "📚 Next Steps:"
echo ""
echo "  1. Validate your setup:"
echo "     Open: labs/0-validate-setup.ipynb"
echo ""
echo "  2. Start with the labs:"
echo "     • Read: Introduction (labs/0-introduction.ipynb)"
echo "     • Lab 1: Local Red Teaming (labs/1-local-scan/)"
echo "     • Lab 2: Cloud Red Teaming (labs/2-cloud-scan/)"
echo "     • Lab 3: Agent Red Teaming (labs/3-scan-agent/)"
echo ""
echo "  3. Make sure you're authenticated:"
echo "     az login"
echo ""
echo "========================================================================="
echo ""
