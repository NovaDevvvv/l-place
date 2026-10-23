--!nonstrict
--!nocheck
--!nolint

local api = {}

local function Log(text, type)
    type = type or "INFO"
    print(`[ {os.date("%Y-%m-%d %H:%M:%S")} ] {string.upper(type)}: {text}`)
end

api.log = Log

return function(game)
    return api
end

