return; -- Gotta make the lua invalid to not format
local smth = {
	"plugin/url",
}

return { "third/url" }

return {
	{
		"plugin/url",
	},
	{
		"other/url",
	},
	smth,
}
