"""`jobq client`: one request over a real socket; its status and body."""

import http.client

from jobq.deadlines import CLIENT_TIMEOUT_S


def request(
    host: str, port: int, token: str | None, method: str, path: str, body: str | None = None
) -> tuple[int, bytes]:
    """OSError or http.client.HTTPException when no response arrives."""
    connection = http.client.HTTPConnection(host, port, timeout=CLIENT_TIMEOUT_S)
    try:
        headers = {"authorization": f"Bearer {token}"} if token else {}
        payload = None if body is None else body.encode("utf-8")
        if payload is not None:
            headers["content-type"] = "application/json"
        connection.request(method, path, body=payload, headers=headers)
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


def format_reply(status: int, body: bytes) -> str:
    text = body.decode("utf-8", errors="replace")
    return f"{status} {text}" if text else str(status)
