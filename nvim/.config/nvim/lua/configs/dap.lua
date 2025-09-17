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

dap.adapters.lldb = {
	type = "executable",
	command = "/usr/bin/lldb-vscode", -- Adjust this path if lldb-vscode is located elsewhere
	name = "lldb",
}

dap.configurations.rust = {
	{
		name = "Launch",
		type = "lldb",
		request = "launch",
		program = function()
			return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
		end,
		cwd = "${workspaceFolder}",
		stopOnEntry = false,
		args = {},
	},
}

dap.adapters.java = {
	type = "server",
	host = "127.0.0.1",
	port = 5005,
}

dap.configurations.java = {
	{
		type = "java",
		name = "Debug Test",
		request = "launch",
		mainClass = "your.test.ClassName", -- Replace with your test class
	},
}
