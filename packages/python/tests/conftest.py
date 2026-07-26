import json
from pathlib import Path
from typing import Any, Callable

import httpx
import pytest

from neuraldefend import NeuroVerifyClient

FIXTURES = Path(__file__).resolve().parents[3] / "tests" / "fixtures"


def load_case(relative_path: str) -> dict[str, Any]:
    with (FIXTURES / relative_path).open(encoding="utf-8") as handle:
        return json.load(handle)


def response_from_case(case: dict[str, Any], request: httpx.Request) -> httpx.Response:
    if case["body_kind"] == "raw":
        return httpx.Response(
            case["http_status"],
            headers=case["headers"],
            content=case["body"],
            request=request,
        )
    return httpx.Response(
        case["http_status"],
        headers=case["headers"],
        json=case["body"],
        request=request,
    )


@pytest.fixture
def client_for_case() -> Callable[[dict[str, Any]], NeuroVerifyClient]:
    clients = []

    def factory(case: dict[str, Any]) -> NeuroVerifyClient:
        def handler(request: httpx.Request) -> httpx.Response:
            request.read()
            return response_from_case(case, request)

        client = NeuroVerifyClient(
            "test-key",
            base_url="http://test.local",
            max_retries=0,
            transport=httpx.MockTransport(handler),
        )
        clients.append(client)
        return client

    yield factory
    for client in clients:
        client.close()
