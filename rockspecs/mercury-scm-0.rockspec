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
    homepage = "http://github.com/catwell/mercury"
}
dependencies = {
    "lua ~> 5.1",
    "copas ~> 1.1",
    "wsapi ~> 1.5",
    "xavante ~> 2.2",
    "wsapi-xavante ~> 1.5",
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
