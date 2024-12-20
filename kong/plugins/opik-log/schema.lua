local typedefs = require "kong.db.schema.typedefs"
local url = require "socket.url"



return {
    name = "opik-log",
    fields = {
      { protocols = typedefs.protocols },
      { config = {
          type = "record",
          fields = {
            { http_endpoint = typedefs.url({ required = true, encrypted = true, referenceable = true, default = "https://www.comet.com/opik/" }) }, -- encrypted = true is a Kong-Enterprise exclusive feature, does nothing in Kong CE
            { ai_proxy_name = { description = "ai_proxy_name", type = "string", default = "proxy"}, },
            { opik_api_key = { description = "The Opik API key", type = "string", encrypted = true }, },
            { opik_workspace = { description = "The Opik Workspace", type = "string" }, },
            { timeout = { description = "An optional timeout in milliseconds when sending data to the upstream server.", type = "number", default = 10000 }, },
            { keepalive = { description = "An optional value in milliseconds that defines how long an idle connection will live before being closed.", type = "number", default = 60000 }, },
            { queue = typedefs.queue },
            { custom_fields_by_lua = typedefs.lua_code },
          },
          custom_validator = function(config)
            -- check no double userinfo + authorization header
            local parsed_url = url.parse(config.http_endpoint)
            if parsed_url.userinfo and config.headers and config.headers ~= ngx.null then
              for hname, hvalue in pairs(config.headers) do
                if hname:lower() == "authorization" then
                  return false, "specifying both an 'Authorization' header and user info in 'http_endpoint' is not allowed"
                end
              end
            end
            return true
          end,
        },
      },
    },
  }
