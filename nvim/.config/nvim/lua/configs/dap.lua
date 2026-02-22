local dap = require("dap")
local function executable_or_nil(...)
	for _, cmd in ipairs({ ... }) do
		local found = vim.fn.exepath(cmd)
		if found and found ~= "" then
			return found
		end
	end
	return nil
end

local dlv = executable_or_nil("dlv")
if dlv then
	dap.adapters.go = {
		type = "executable",
		command = dlv,
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
end

local lldb = executable_or_nil("lldb-vscode", "lldb-dap")
if lldb then
	dap.adapters.lldb = {
		type = "executable",
		command = lldb,
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
end

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
