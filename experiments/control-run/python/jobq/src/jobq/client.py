"""`jobq client`: one HTTP request, its status and body."""

import http.client
from dataclasses import dataclass

# within: connect, send, and read the whole response in this long (chosen: 10 s).
CLIENT_TIMEOUT_S = 10.0


@dataclass(frozen=True)
class Call:
    """One request: no authorization header when `token` is None."""

    token: str | None
    method: str
    path: str
    body: str | None = None


@dataclass(frozen=True)
class ClientResponse:
    status: int
    body: str


def request(host: str, port: int, call: Call, timeout: float = CLIENT_TIMEOUT_S) -> ClientResponse:
    """Send one request on a fresh connection. OSError when the service cannot be reached."""
    connection = http.client.HTTPConnection(host, port, timeout=timeout)
    headers = {"connection": "close"}
    if call.token is not None:
        headers["authorization"] = f"Bearer {call.token}"
    if call.body is not None:
        headers["content-type"] = "application/json"
    body = None if call.body is None else call.body.encode()
    try:
        connection.request(call.method, call.path, body, headers)
        response = connection.getresponse()
        data = response.read()
    except http.client.HTTPException as broken:
        raise OSError(f"bad response: {broken}") from broken
    finally:
        connection.close()
    return ClientResponse(response.status, data.decode("utf-8", errors="replace"))


def render(response: ClientResponse) -> str:
    """The status on one line, then the body on the next when there is one."""
    return f"{response.status}\n{response.body}\n" if response.body else f"{response.status}\n"
