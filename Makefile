.PHONY: mineblock deploy clean clean-all

ANVIL_RPC ?= http://127.0.0.1:8545

mineblock:
	cast rpc --rpc-url $(ANVIL_RPC) anvil_mine 0xa

deploy:
	mkdir -p deployments
	forge script script/DeployWell.s.sol:DeployWell \
		--rpc-url $(ANVIL_RPC) --broadcast --slow -vvv

clean:
	forge clean && rm -rf broadcast cache

clean-all:
	forge clean && rm -rf broadcast cache deployments

