-- You can also define your application in a dedicated environment
-- where route functions are accessible.
-- The name of this sample is historic.

local mercury = require 'mercury'

return mercury.application('no_pollution', function()
    local app_name = _NAME

    get('/', function()
        return string.format('<h1>Welcome to %s!</h1>', app_name)
    end)

    get('/hello/:name', function()
        return string.format('Hello %s!', params.name)
    end)
end)
