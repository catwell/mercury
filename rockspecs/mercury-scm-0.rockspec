package = "mercury"
version = "scm-0"
source = {
    url = "git://github.com/catwell/mercury.git"
}
description = {
    summary = "A small framework for creating web apps in Lua",
    detailed = [[
        Mercury aims to be a Sinatra-like web framework (or DSL, if you like)
        for creating web applications in Lua, quickly and painlessly.
    ]],
    license = "MIT/X11",
    homepage = "https://github.com/catwell/mercury"
}
dependencies = {
    "lua ~> 5.1",
    "copas ~> 1.2",
    "wsapi ~> 1.7",
    "xavante ~> 2.4",
    "wsapi-xavante ~> 1.7",
}

build = {
    type = "none",
    install = {
        lua = {
            "mercury.lua",
            ["mercury.lp"] = "lp.lua",
        },
        bin = {
            ["mercury"] = "bin/mercury",
        }
    }
}
