std = "lua51"

exclude_files = {
    ".lua",
    "samples" -- for now
}

ignore = {
    -- allow unused variables ending with _
    "211/.*_",
    -- allow unused arguments ending with _
    "212/.*_",
    -- allow never accessed variables ending with _
    "231/.*_",
}
