local Queue = require "kong.tools.queue"
local cjson = require "cjson"
local url = require "socket.url"
local http = require "resty.http"
local sandbox = require "kong.tools.sandbox".sandbox
local kong_meta = require "kong.meta"
local uuid7 = require "kong.plugins.opik-log.uuid7"

local kong = kong
local fmt = string.format


local function create_trace_url(conf)
  local trace_url = conf.http_endpoint .. "api/v1/private/traces/batch"
  return trace_url
end

local function create_span_url(conf)
  local span_url = conf.http_endpoint .. "api/v1/private/spans/batch"
  return span_url
end

local function convert_messages_to_spans(conf, messages)
  local spans = {}
  
  for _, message in ipairs(messages) do
    -- Note, unclear if the string should be "proxy" or "ai-proxy"
    local ai_data = message.ai and message.ai["proxy"] or {}
    local ai_payload = ai_data.payload or {}
    local request_payload = cjson.decode(ai_payload["request"])
    local response_payload = cjson.decode(ai_payload["response"])
    local usage_payload = ai_data.usage or {}
    local meta_payload = ai_data.meta or {}

    -- Convert Unix timestamp to ISO 8601
    local start_time = os.date("!%Y-%m-%dT%H:%M:%S.000Z", math.floor(message.started_at / 1000))
    local end_time = os.date("!%Y-%m-%dT%H:%M:%S.000Z", math.floor((message.started_at + (message.latencies.request or 0)) / 1000))
    
    table.insert(spans, {
      name = "kong_llm_call",
      trace_id = message.opik_uuid,
      type = "llm",
      start_time = start_time,
      end_time = end_time,
      input = request_payload,
      output = response_payload,
      model = meta_payload.response_model,
      provider = meta_payload.provider_name,
      usage = {
        prompt_tokens = usage_payload.prompt_tokens,
        completion_tokens = usage_payload.completion_tokens,
        total_tokens = usage_payload.total_tokens
      }
    })
  end
  
  return spans
end

local function convert_messages_to_traces(conf, messages)
  local traces = {}
  
  for _, message in ipairs(messages) do
    -- Note, unclear if the string should be "proxy" or "ai-proxy"
    local ai_data = message.ai and message.ai["proxy"] or {}
    local ai_payload = ai_data.payload or {}
    local request_payload = cjson.decode(ai_payload["request"])
    local response_payload = cjson.decode(ai_payload["response"])
    
    -- Convert Unix timestamp to ISO 8601
    local start_time = os.date("!%Y-%m-%dT%H:%M:%S.000Z", math.floor(message.started_at / 1000))
    local end_time = os.date("!%Y-%m-%dT%H:%M:%S.000Z", math.floor((message.started_at + (message.latencies.request or 0)) / 1000))
    
    table.insert(traces, {
      id = message.opik_uuid,
      name = "kong_llm_call",
      start_time = start_time,
      end_time = end_time,
      input = request_payload,
      output = response_payload
    })
  end
  
  kong.log.debug("Traces: ", cjson.encode(traces))
  return traces
end

-- Sends the provided entries to the configured plugin host
-- @return true if everything was sent correctly, falsy if error
-- @return error message if there was an error
local function send_entries(conf, payload)
  local timeout = conf.timeout
  local keepalive = conf.keepalive
  local content_type = conf.content_type
  local opik_workspace = conf.opik_workspace
  local opik_api_key = conf.opik_api_key
  

  local httpc = http.new()
  httpc:set_timeout(timeout)

  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = opik_api_key,
    ["Comet-Workspace"] = opik_workspace
  }
  
  -- Send trace
  local trace_endpoint_batch = create_trace_url(conf)
  local res, err = httpc:request_uri(trace_endpoint_batch, {
    method = "POST",
    headers = headers,
    body = cjson.encode({ traces = convert_messages_to_traces(conf, payload) }),
    keepalive_timeout = keepalive,
    ssl_verify = false,
  })
  if not res then
    return nil, "failed request to " .. trace_endpoint_batch .. ": " .. err
  end

  kong.log.debug(fmt("http-log sent data log server, %s HTTP status %d",
  trace_endpoint_batch, res.status))

  kong.log.debug("Response headers:")
  for k, v in pairs(res.headers) do
    kong.log.debug(fmt("%s: %s", k, v))
  end

  -- Send spans
  local span_endpoint_batch = create_span_url(conf)
  local res, err = httpc:request_uri(span_endpoint_batch, {
    method = "POST",
    headers = headers,
    body = cjson.encode({ spans = convert_messages_to_spans(conf, payload) }),
    keepalive_timeout = keepalive,
    ssl_verify = false,
  })
  if not res then
    return nil, "failed request to " .. span_endpoint_batch .. ": " .. err
  end

  -- always read response body, even if we discard it without using it on success
  local response_body = res.body

  kong.log.debug(fmt("http-log sent data log server, %s HTTP status %d",
  span_endpoint_batch, res.status))

  if res.status < 300 then
    return true

  else
    return nil, "request to " .. conf.http_endpoint .. " returned status code " .. tostring(res.status) .. " and body " .. response_body
  end
end

-- The PRIORITY number is important, if set too high, the request and response
-- will not be logged
local OpikLogHandler = {
  PRIORITY = 9,
  VERSION = "0.0.1",
}

local function make_queue_name(conf)
  return fmt("%s:%s:%s:%s",
    conf.http_endpoint,
    conf.timeout,
    conf.keepalive,
    conf.flush_timeout)
end



function OpikLogHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression)())
    end
  end
  
  local queue_conf = Queue.get_plugin_params("http-log", conf, make_queue_name(conf))

  local message = kong.log.serialize()
  message.opik_uuid = uuid7.uuidv7()

  local ok, err = Queue.enqueue(
    queue_conf,
    send_entries,
    conf,
    message
  )
  if not ok then
    kong.log.err("Failed to enqueue log entry to log server: ", err)
  end
end

return OpikLogHandler
