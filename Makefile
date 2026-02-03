.PHONY: anvil clean clean-all deploy deploy-all deploy-infra fulfill mineblock offer simulate

include .env

ANVIL_RPC ?= http://127.0.0.1:8545
NUM_ACCOUNTS ?= 50

anvil:
	anvil --accounts $(NUM_ACCOUNTS) --balance 10000

clean:
	forge clean && rm -rf broadcast cache

clean-all:
	forge clean && rm -rf broadcast cache deployments

# Full local deploy: infrastructure + wrapper + well
deploy-all: deploy-infra deploy

# Deploy VRF infrastructure (LOCAL ONLY)
# Creates coordinator, link mock, price feed, and subscription
deploy-infra:
	mkdir -p deployments
	forge script script/DeployInfra.s.sol:DeployInfra \
		--rpc-url $(ANVIL_RPC) --broadcast -vvv

# Deploy wrapper (if local) and Well
# Local: reads subId from SubscriptionCreated event logs
# Remote: uses VRF_WRAPPER env var
deploy:
	mkdir -p deployments
	@if [ -f deployments/infra.json ]; then \
		COORD=$$(jq -r '.coordinator' deployments/infra.json); \
		SUB_ID=$$(cast logs --from-block 0 --to-block latest \
			--address $$COORD \
			"SubscriptionCreated(uint256,address)" \
			--rpc-url $(ANVIL_RPC) --json | jq -r '.[-1].topics[1]' | cast to-dec); \
		echo "Using SUB_ID: $$SUB_ID"; \
		SUB_ID=$$SUB_ID forge script script/DeployWell.s.sol:DeployWell \
			--rpc-url $(ANVIL_RPC) --broadcast -vvv; \
	else \
		forge script script/DeployWell.s.sol:DeployWell \
			--rpc-url $(ANVIL_RPC) --broadcast -vvv; \
	fi

mineblock:
	cast rpc --rpc-url $(ANVIL_RPC) anvil_mine 0xa

simulate:
	forge script script/SimulateWell.s.sol:SimulateWell \
		--rpc-url $(ANVIL_RPC) --broadcast -vvv

# Make an offering to the Well
# Usage: make offer PK=<private_key> IMPRINT=<0-9999>
# Example: make offer PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 IMPRINT=42
offer:
	VISITOR_PK=$(PK) IMPRINT=$(IMPRINT) forge script script/interactions/MakeOffering.s.sol:MakeOffering \
		--rpc-url $(ANVIL_RPC) --broadcast -vvv

# Fulfill VRF request (LOCAL ONLY - uses mock coordinator)
# Usage: make fulfill REQUEST_ID=<id> [RANDOM_WORD=<number>]
# Example: make fulfill REQUEST_ID=1 RANDOM_WORD=42
fulfill:
	REQUEST_ID=$(REQUEST_ID) RANDOM_WORD=$(RANDOM_WORD) forge script script/interactions/FulfillVRF.s.sol:FulfillVRF \
		--rpc-url $(ANVIL_RPC) --broadcast -vvv
