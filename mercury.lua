local wsapi = require 'wsapi'
wsapi.request = require 'wsapi.request'
wsapi.response = require 'wsapi.response'
wsapi.util = require 'wsapi.util'

local route_env   = setmetatable({ }, { __index = _G })
local route_table = { GET = {}, POST = {}, PUT = {}, DELETE = {} }

local function set_helper(environment, name, method)
    if type(method) ~= 'function' then
        error('"' .. name .. '" is an invalid helper, only functions are allowed.')
    end
    environment[name] = method
end

--
-- *** templating *** --
--

local function merge_tables(...)
    local numargs, out = select('#', ...), {}
    for i = 1, numargs do
        local t = select(i, ...)
        if type(t) == "table" then
            for k, v in pairs(t) do out[k] = v end
        end
    end
    return out
end

local templating_engines = {
    cosmo    = function(template, values)
        local cosmo = require 'cosmo'
        return function()
            return cosmo.fill(template, values)
        end
    end,
    string   = function(template, ...)
        local arg = {...}
        return function()
            return string.format(template, table.unpack(arg))
        end
    end,
    lp       = function(template, values)
        return function()
            local lp = require 'cgilua.lp'
            lp.setoutfunc("mercury_lp_write")
            local t = {}
            local function of(...)
                local numargs = select('#', ...)
                for i = 1, numargs do
                    local s = select(i, ...)
                    table.insert(t, s)
                end
            end
            lp.compile(
                template, template,
                setmetatable(
                    merge_tables(route_env, values, {mercury_lp_write = of}),
                    {__index = _G}
                )
            )()
            return table.concat(t)
        end
    end,
    codegen  = function(template, top, values)
        local CodeGen = require 'CodeGen'
        return function()
            local tmpl = CodeGen(template, values, route_env)
            return tmpl(top)
        end
    end,
}

local template = setmetatable({ }, {
    __index = function(env_, name)
        local engine = templating_engines[name]

        if type(engine) == nil then
            error('cannot find template renderer "'.. name ..'"')
        end

        return function(...)
            coroutine.yield({ template = engine(...) })
        end
    end
})

--
-- *** application *** --
--

local function error_500(response, output)
    response.status  = 500
    response.headers = { ['Content-type'] = 'text/html' }
    response:write(
        '<pre>An error has occurred while serving this page.\n\n' ..
        'Error details:\n' .. output:gsub("\n", "<br/>") ..
        '</pre>'
    )
    return response:finish()
end

local function compile_url_pattern(pattern)
    local compiled_pattern = {
        original = pattern,
        params   = { },
    }

    -- Lua pattern matching is blazing fast compared to regular expressions,
    -- but at the same time it is tricky when you need to mimic some of
    -- their behaviors.
    pattern = pattern:gsub("[%(%)%.%%%+%-%%?%[%^%$%*]", function(char)
        if char == '*' then return ':*' else return '%' .. char end
    end)

    pattern = pattern:gsub(':([%w%*]+)(/?)', function(param, slash)
        if param == '*' then
            table.insert(compiled_pattern.params, 'splat')
            return '(.-)' .. slash
        else
            table.insert(compiled_pattern.params, param)
            return '([^/?&#]+)' .. slash
        end

    end)

    if pattern:sub(-1) ~= '/' then pattern = pattern .. '/' end
    compiled_pattern.pattern = '^' .. pattern .. '?$'

    return compiled_pattern
end

local function add_route(verb, path, handler, options)
    table.insert(route_table[verb], {
        pattern = compile_url_pattern(path),
        handler = handler,
        options = options,
    })
end

local function extract_parameters(pattern, matches)
    local params = { }
    for i,k in ipairs(pattern.params) do
        if (k == 'splat') then
            if not params.splat then params.splat = {} end
            table.insert(params.splat, wsapi.util.url_decode(matches[i]))
        else
            params[k] = wsapi.util.url_decode(matches[i])
        end
    end
    return params
end

local function extract_post_parameters(request, params)
    for k,v in pairs(request.POST) do
        if not params[k] then params[k] = v end
    end
end

local function url_match(pattern, path)
    local matches = { string.match(path, pattern.pattern) }
    if #matches > 0 then
        return true, extract_parameters(pattern, matches)
    else
        return false, nil
    end
end

local function prepare_route(route, request, response, params)
    route_env.params   = params
    route_env.request  = request
    route_env.response = response
    return route.handler
end

local function router(application_, state, request, response)
    local verb, path = state.vars.REQUEST_METHOD, state.vars.PATH_INFO

    return coroutine.wrap(function()
        local routes = verb == "HEAD" and route_table["GET"] or route_table[verb]
        for _, route in ipairs(routes) do
            local match, params = url_match(route.pattern, path)
            if match then
                if verb == 'POST' then extract_post_parameters(request, params) end
                coroutine.yield(prepare_route(route, request, response, params))
            end
        end
    end)
end

local function initialize(application, wsapi_env)
    -- TODO: Taken from Orbit! It will change soon to adapt request
    --       and response to a more suitable model.
    local web = {
        status   = 200,
        headers  = { ["Content-Type"]= "text/html" },
        cookies  = {}
    }

    web.vars     = wsapi_env
    web.prefix   = application.prefix or wsapi_env.SCRIPT_NAME
    web.suffix   = application.suffix
    web.doc_root = wsapi_env.DOCUMENT_ROOT

    if wsapi_env.APP_PATH == '' then
        web.real_path = application.real_path or '.'
    else
        web.real_path = wsapi_env.APP_PATH
    end

    local wsapi_req = wsapi.request.new(wsapi_env)
    local wsapi_res = wsapi.response.new(web.status, web.headers)

    web.set_cookie = function(_, name, value)
        wsapi_res:set_cookie(name, value)
    end

    web.delete_cookie = function(_, name, path)
        wsapi_res:delete_cookie(name, path)
    end

    web.path_info = wsapi_req.path_info

    if not wsapi_env.PATH_TRANSLATED == '' then
        web.path_translated = wsapi_env.PATH_TRANSLATED
    else
        web.path_translated = wsapi_env.SCRIPT_FILENAME
    end

    web.script_name = wsapi_env.SCRIPT_NAME
    web.method      = string.lower(wsapi_req.method)
    web.input       = wsapi_req.params
    web.cookies     = wsapi_req.cookies

    return web, wsapi_req, wsapi_res
end

local function run(application, wsapi_env)
    local state, request, response = initialize(application, wsapi_env)

    for route in router(application, state, request, response) do
        local coroute = coroutine.create(route)
        local success, output = coroutine.resume(coroute, route_env.params, route_env)

        if not success then
            return error_500(response, output)
        end

        if not output then
            -- render an empty body
            return response:finish()
        end

        local output_type = type(output)
        if output_type == 'function' then
            -- First attempt at streaming responses using coroutines.
            -- TODO untested
            return response.status, response.headers, coroutine.wrap(output)
        elseif output_type == 'string' then
            response:write(output)
            return response:finish()
        elseif output.template then
            response:write(output.template() or 'template rendered an empty body')
            return response:finish()
        elseif not output.pass then
            return error_500(response, output)
        end
    end

    local function emit_no_routes_matched()
        coroutine.yield('<html><head><title>ERROR</title></head><body>')
        coroutine.yield('Sorry, no route found to match ' .. request.path_info .. '<br /><br/>')
        if application.debug_mode then
            coroutine.yield('<code><b>REQUEST DATA:</b><br/>' .. tostring(request) .. '<br/><br/>')
            coroutine.yield('<code><b>RESPONSE DATA:</b><br/>' .. tostring(response) .. '<br/><br/>')
        end
        coroutine.yield('</body></html>')
    end

    return 404, { ['Content-type'] = 'text/html' }, coroutine.wrap(emit_no_routes_matched)
end

local application_methods = {
    get    = function(path, method, options_) add_route('GET', path, method) end,
    post   = function(path, method, options_) add_route('POST', path, method) end,
    put    = function(path, method, options_) add_route('PUT', path, method) end,
    delete = function(path, method, options_) add_route('DELETE', path, method) end,
    helper  = function(name, method) set_helper(route_env, name, method) end,
    pass = function() coroutine.yield({ pass = true }) end,
}

local function app(application)
    if type(application) == 'string' then
        application = { _NAME = application }
    else
        application = application or {}
    end

    for k, v in pairs(application_methods) do
        application[k] = v
    end

    application.run = function(wsapi_env)
        return run(application, wsapi_env)
    end

    return setmetatable(application, {__index = _G})
end

return setmetatable(
    {application = app, t = template},
    {__index = application_methods}
)
