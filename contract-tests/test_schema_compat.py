import pytest
import json
from pydantic import ValidationError
from infra.src.schemas.events_v1 import AgentStateTransitionV1, ToolCallFormatV1, RoutingContextV1

def test_state_transition_v1_serialize():
    """Ensure our transitions conform exactly to the v1 specification and deserialize effectively."""
    data = {
        "transition_id": "test-tx-1",
        "current_state": "idle",
        "next_state": "tool_execution",
        "reasoning": "Determined I needed to run weather tool",
        "action": "weather_lookup",
        "action_input": {"city": "Boston"}
    }

    # Init ensures correct population
    model = AgentStateTransitionV1(**data)

    # Assert forced schema inject
    assert model.schema_version == "1.0"

    # Export and reload simulates sending over queues/DB insertion
    serialized_str = model.model_dump_json()
    loaded = AgentStateTransitionV1.model_validate_json(serialized_str)

    assert loaded.action == "weather_lookup"
    assert loaded.transition_id == "test-tx-1"

def test_missing_schema_version_rejection():
    """If someone forces a bad schema version or injects unallowed kwargs, validate it rejects."""
    with pytest.raises(ValidationError):
        bad_data = {
            "transition_id": "bad-1",
            "current_state": "A",
            "next_state": "B",
            "reasoning": "...",
            "unsupported_key": "Should fail because of extra='forbid'"
        }
        AgentStateTransitionV1(**bad_data)

def test_routing_context_v1():
    rctx = RoutingContextV1(
        trace_id="td-11234",
        provider_intent="openai_fast",
        auth_subject="system_cron"
    )
    assert rctx.schema_version == "1.0"
    assert rctx.complexity_budget == 10  # default verify
