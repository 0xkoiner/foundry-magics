test-errors-lib:
	forge test --mc TestErrorsLib -vv
test-events-lib:
	forge test --mc TestEventsLib -vv
deterministic-deployment:
	forge script ./script/DeterministicDeployment.s.sol -vv