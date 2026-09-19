"""Bounded candidate schema and deliberately small public result projection."""
import base64
import json
import math
import re

VERSION = 'mo-workspace-http-v1'
REQUEST_CAP = 851968
RESPONSE_CAP = 524288
JOURNAL_CAP = 4 * 1024 * 1024
ID = re.compile(r'[A-Za-z0-9_-]{1,64}\Z', re.ASCII)
HEX = re.compile(r'[0-9a-f]{32}\Z', re.ASCII)
STATES = {'success', 'refusal', 'failure', 'timeout', 'cancellation'}
EXECUTIONS = {'not_started', 'completed', 'unknown'}
CORE_ERRORS = frozenset('invalid_path invalid_utf8 oversized unsupported_entry unsupported_mode empty_old multiple_matches missing_match snapshot_mode too_many_entries quota empty_search invalid_import path_conflict deadline cleanup_required quarantined closed result_too_large filesystem_refusal controller_failure request_refused transport_unknown recovery_closed duplicate_call'.split())
ERRORS = CORE_ERRORS | frozenset('malformed unauthorized unbound not_found method unsupported_media conflict busy admission_closed call_limit journal_full response_timeout owner_unknown output_encoding invalid_result response_too_large'.split())
ARGS = {
    'list_files': (set(), {'path'}), 'read_file': ({'path'}, set()),
    'search': ({'query'}, {'path'}), 'write_file': ({'path', 'text'}, set()),
    'exact_edit': ({'path', 'old_text', 'new_text'}, set()),
    'command': ({'command', 'timeout_ms'}, set()),
}

class Refused(ValueError):
    def __init__(self, error='malformed', status=400):
        self.error, self.status = error, status
        super().__init__(error)


def encode(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(',', ':')).encode('ascii')


def decode(raw):
    def pairs(rows):
        value = {}
        for key, item in rows:
            if key in value:
                raise Refused()
            value[key] = item
        return value
    def constant(_):
        raise Refused()
    try:
        value = json.loads(raw.decode('utf-8', errors='strict'), object_pairs_hook=pairs, parse_constant=constant)
        # Also reject escaped unpaired surrogates anywhere, including keys.
        def strings(item):
            if isinstance(item, str):
                item.encode('utf-8', errors='strict')
            elif isinstance(item, dict):
                for key, child in item.items():
                    strings(key)
                    strings(child)
            elif isinstance(item, list):
                for child in item:
                    strings(child)
        strings(value)
        return value
    except (ValueError, UnicodeError, RecursionError):
        raise Refused() from None


def request(raw, run_id, workspace_id):
    if not 0 < len(raw) <= REQUEST_CAP:
        raise Refused('oversized', 413)
    value = decode(raw)
    if type(value) is not dict or set(value) != {'version', 'run_id', 'workspace_id', 'call_id', 'operation', 'args'}:
        raise Refused()
    if value['version'] != VERSION:
        raise Refused()
    for key, pattern in (('run_id', ID), ('workspace_id', HEX), ('call_id', ID)):
        if type(value[key]) is not str or not pattern.fullmatch(value[key]):
            raise Refused()
    if value['run_id'] != run_id or value['workspace_id'] != workspace_id:
        raise Refused('unbound', 403)
    operation, args = value['operation'], value['args']
    if type(operation) is not str or operation not in ARGS or type(args) is not dict:
        raise Refused()
    required, optional = ARGS[operation]
    if not required <= set(args) <= required | optional:
        raise Refused()
    for key, item in args.items():
        if key == 'timeout_ms':
            if type(item) is not int or not 500 <= item <= 120000:
                raise Refused()
        elif type(item) is not str:
            raise Refused()
    return value


def envelope(request=None, *, accepted=False, state='refusal', execution='not_started', error=None, result=None):
    return dict(version=VERSION, **{key: request[key] if request else None for key in ('run_id', 'workspace_id', 'call_id')},
                accepted=accepted, state=state, execution=execution, error=error, result=result)


def project(req, core):
    """Never expose core manifests, observations, exception text or host paths."""
    state, execution = core.get('state'), core.get('execution')
    if state not in STATES or execution not in EXECUTIONS:
        return envelope(req, accepted=True, state='failure', execution='unknown', error='invalid_result')
    error = core.get('error')
    if error is not None and error not in CORE_ERRORS:
        error = 'controller_failure'
    result = None
    if req['operation'] == 'command':
        result = {key: core.get(key) for key in ('exit_code', 'signal', 'execution_valid')}
        result.update(stdout=None, stderr=None, encoding='utf-8', truncated=bool(core.get('truncated')), elapsed_ms=None)
        elapsed = core.get('elapsed_seconds')
        if type(elapsed) in (int, float) and math.isfinite(elapsed) and elapsed >= 0:
            result['elapsed_ms'] = math.floor(elapsed * 1000)
        try:
            if core.get('encoding') != 'base64':
                raise ValueError()
            streams = [base64.b64decode(core[key], validate=True) for key in ('stdout', 'stderr')]
            if sum(map(len, streams)) > 65536:
                raise ValueError()
            result['stdout'], result['stderr'] = [stream.decode('utf-8', errors='strict') for stream in streams]
        except (KeyError, ValueError, TypeError, UnicodeError):
            state, error = 'failure', 'output_encoding'
    elif isinstance(core.get('result'), dict):
        source = core['result']
        op = req['operation']
        keys = {'list_files': ('items',), 'search': ('items',), 'read_file': ('text',),
                'write_file': ('written',), 'exact_edit': ('edited',)}[op]
        result = {key: source[key] for key in keys if key in source}
        result['truncated'] = bool(core.get('truncated') or source.get('truncated'))
    response = envelope(req, accepted=True, state=state, execution=execution, error=error, result=result)
    if len(encode(response)) > RESPONSE_CAP:
        response.update(state='refusal', error='response_too_large', result=None)
    return response
