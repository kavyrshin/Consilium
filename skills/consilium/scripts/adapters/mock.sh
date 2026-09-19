# Adapter: mock agent. Calls no model and needs no keys; it writes a well-formed
# placeholder review / decision / report. Use it to see the whole pipeline work
# (`CM_REVIEWERS=mock CM_ARBITERS=mock ...`) and in the test suite.
# CM_MOCK_MODE: success (default) | fail | hang | delete | stdout

adapter_label() { echo "Mock"; }
adapter_models() { echo "mock-1"; }
adapter_command() {
  CM_CMD=(bash "$CM_SKILL_DIR/scripts/mock-agent.sh" "${CM_MOCK_MODE:-success}")
}
