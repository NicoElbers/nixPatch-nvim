return; -- Gotta make the lua invalid to not format
local smth = {
	dir = [[plugin/path]], name = [[plugin-name]],
}

return { dir = [[third/path]], name = [[third-name]] }

return {
	{
		dir = [[plugin/path]], name = [[plugin-name]],
	},
	{
		dir = [[other/path]], name = [[other-name]],
	},
	smth,
}
