# Opik - Kong plugin

## Introduction
[Kong](https://docs.konghq.com/gateway/latest/ai-gateway/) is an open-source API gateway that can be easily extended to act as an LLM proxy, allowing you to use AI models from the comfort of your API Gateway.

The Opik plugin allows you to log all AI Gateway requests to the Opik platform. This allows you to monitor, analyze and debug you AI Gateway requests without requiring users to manually log their requests.

It is meant to be used in conjunction with the [AI Proxy](https://docs.konghq.com/hub/kong-inc/ai-proxy/) is a Kong plugin that allows you to proxy LLM calls to multiple LLM providers using a standardized format.

### How it works

The Opik plugin works by intercepting all requests made to the AI Gateway and logging them in a standardized format to the Opik platform. The pluging will automatically log the following information:

- Request payload: This is the list of messages and LLM parameters submited by the user
- Response payload: This is the response from the LLM provider
- Model used: This is the name of the model that was used to generate the response
- Usage payload: The number of tokens used by the LLM provider to generate the response

You can learn more about the LLM providers supported by the Kong AI proxy plugin [here](https://docs.konghq.com/hub/kong-inc/ai-proxy/).

### Get started with the Opik plugin

To install the Opik plugin, you need to add it to your Kong configuration file. You can find more information on how to install plugins in the [Kong documentation](https://docs.konghq.com/gateway/3.9.x/plugin-development/distribution/#packaging-sources).

The full configuration option for this plugin can be found below.

**Note:** In order to log the payload request and response, you will need to enable the [`logging.payload_logs`](https://docs.konghq.com/hub/kong-inc/ai-proxy/configuration/#config-logging-log_payloads) option in the AI Proxy plugin.

## Configuration

The Opik-Log plugin has the following configuration options:

- `http_endpoint`: (Required, Encrypted, Referenceable) The endpoint URL where logs will be sent. Defaults to "https://www.comet.com/opik/". Note: encryption is only available in Kong Enterprise.
- `ai_proxy_name`: (Required) The name of the AI proxy. Defaults to "proxy".
- `opik_api_key`: (Required, Encrypted) The Opik API key for authentication.
- `opik_workspace`: (Required) The Opik Workspace identifier.
- `timeout`: Timeout in milliseconds when sending data to the upstream server. Defaults to 10000ms (10 seconds).
- `keepalive`: Duration in milliseconds that defines how long an idle connection will live before being closed. Defaults to 60000ms (60 seconds).

## Using the plugin

To install the plugin, will need to clone this repository and follow the instructions in the [Kong documentation](https://docs.konghq.com/gateway/3.9.x/plugin-development/distribution/#packaging-sources).

If you are using the Kong Admin API, you can use the following command to install the plugin:

```bash
curl -is -X POST http://localhost:8001/services/{serviceName|Id}/plugins \
    --header "accept: application/json" \
  --header "Content-Type: application/json" \
  --data '
  {
    "name": "opik-log",
    "config": {
      "opik_api_key": "<Replace with your Opik API key>",
      "opik_workspace": "<Replace with your Opik workspace>"
    }
  }'
```

**Note:** This plugin is currently in public preview, if you would like us to support additional features please create an issue [here](https://github.com/comet-ml/opik/issues).

## Developing the pluging

You can use the `pongo` development environment to develop the plugin. You can learn more about the pongo development environment and how to install it [here](https://github.com/Kong/kong-pongo?tab=readme-ov-file#installation).

Once you have pongo installed you can run the following command **from the opik-kong-plugin directory** to start the development environment:

1. Start the pongo development environment
```bash
pongo up
```

2. Launch the Gateway and open a shell with it:

```bash
pongo shell
```

3. Once the gateway is running, you can start by checking the Opik log plugin is available:

```bash
curl -s localhost:8001 | \
  jq '.plugins.available_on_server."opik-log"'
```

This should return the plugin version and priority

4. You can now configure the AI gateway and Opik log plugin:

```bash
curl -i -X POST http://localhost:8001/services/llm_service/routes \
  --data name="openai-llm" \
  --data paths="/openai"

curl -i -X POST http://localhost:8001/routes/openai-llm/plugins \
  --header "accept: application/json" \
  --header "Content-Type: application/json" \
  --data '
  {
    "name": "ai-proxy",
    "config": {
      "route_type": "llm/v1/chat",
      "model": {
        "provider": "openai"
      },
      "logging": {
        "log_payloads": true,
        "log_statistics": true
      }
    }
  }'

curl -is -X POST http://localhost:8001/routes/openai-llm/plugins \
    --header "accept: application/json" \
  --header "Content-Type: application/json" \
  --data '
  {
    "name": "opik-log",
    "config": {
      "opik_api_key": "<Replace with your Opik API key>",
      "opik_workspace": "jacques-comet"
    }
  }'
```

5. You can call the AI gateway and check the logs of the Opik log plugin:

```bash
curl --http1.1 http://localhost:8000/openai \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer <OPENAI_API_KEY>" \
  --data '{
     "model": "gpt-4o-mini",
     "messages": [{"role": "user", "content": "Say this is a test!"}]
   }'
```

and 

```bash
cat /kong-plugin/servroot/logs/error.log
```
