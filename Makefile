.PHONY: anvil clean clean-all deploy mineblock simulate

include .env

ANVIL_RPC ?= http://127.0.0.1:8545
NUM_ACCOUNTS ?= 50

anvil:
	anvil --accounts $(NUM_ACCOUNTS) --balance 10000

clean:
	forge clean && rm -rf broadcast cache

clean-all:
	forge clean && rm -rf broadcast cache deployments

deploy:
	mkdir -p deployments
	forge script script/DeployWell.s.sol:DeployWell \
		--rpc-url $(ANVIL_RPC) --broadcast --slow -vvv

mineblock:
	cast rpc --rpc-url $(ANVIL_RPC) anvil_mine 0xa

simulate:
	forge script script/SimulateWell.s.sol:SimulateWell \
		--rpc-url $(ANVIL_RPC) --broadcast -vvv
