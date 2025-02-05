local dap = require("dap")
dap.adapters.go = {
	type = "executable",
	command = "${pkgs.delve}/bin/dlv",
	args = { "dap" },
}
dap.configurations.go = {
	{
		type = "go",
		name = "Debug",
		request = "launch",
		program = "${file}",
	},
}
