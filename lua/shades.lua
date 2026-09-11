local M = {}

M.set_color = nil
M.socket_path = "/tmp/theme-change.sock"
M.current_theme = nil
M._theme_callbacks = {}

-- Function to apply theme (or any other configuration provided by the user)
function M.apply_theme(theme)
	if M.set_color then
		M.set_color(theme)
	end
end

function M.listen()
	local function _process_message(message)
		-- only the first colon delimits the verb; a noun may contain colons of its own
		local verb, noun = message:match("^([^:]+):(.*)$")
		if not verb then
			return
		end

		if verb == "set" then
			vim.schedule(function()
				M.current_theme = noun
				M.apply_theme(noun)
				-- flush any callbacks waiting on the initial theme
				local callbacks = M._theme_callbacks
				M._theme_callbacks = {}
				for _, cb in ipairs(callbacks) do
					cb(M.current_theme)
				end
			end)
		end
	end

	local pipe, pipe_err = vim.loop.new_pipe(true)
	if pipe_err then
		vim.notify("shades.nvim: error creating pipe: " .. pipe_err, vim.log.levels.ERROR)
		return
	end

	pipe:connect(M.socket_path, function(connect_err)
		if connect_err then
			vim.notify("shades.nvim: connection error: " .. connect_err, vim.log.levels.ERROR)
			return
		end

		local buffer = ""
		pipe:read_start(function(read_err, data)
			if read_err then
				vim.notify("shades.nvim: read error: " .. read_err, vim.log.levels.ERROR)
				return
			end

			if not data then
				return
			end

			-- the read boundary is arbitrary, so a read can hold several messages,
			-- part of one, or both. Everything up to the last "\n" is complete;
			-- whatever trails it stays buffered for the next read. Nothing is
			-- trimmed before the split, because that would eat the delimiter.
			buffer = buffer .. data

			local parts = vim.split(buffer, "\n")
			for i = 1, #parts - 1 do
				local message = vim.trim(parts[i])
				if message ~= "" then
					_process_message(message)
				end
			end
			buffer = parts[#parts]
		end)

		-- write the subscribe message in
		pipe:write("subscribe:neovim\n", function(write_err)
			if write_err then
				vim.notify("shades.nvim: write error: " .. write_err, vim.log.levels.ERROR)
			end
		end)
		-- ask for the current theme
		pipe:write("get:\n", function(write_err)
			if write_err then
				vim.notify("shades.nvim: write error: " .. write_err, vim.log.levels.ERROR)
			end
		end)
	end)
end

function M.get(callback)
	if M.current_theme then
		callback(M.current_theme)
	else
		-- theme not yet received from socket; queue until listen() gets the response
		table.insert(M._theme_callbacks, callback)
	end
end

-- Function to setup user's configuration
function M.setup(config)
	if type(config) ~= "table" then
		error("shades.nvim: invalid configuration table provided.")
	end

	if type(config.set_color) == "function" then
		M.set_color = config.set_color
	else
		error("shades.nvim: expected 'set_color' to be a function in the configuration table.")
	end

	if config.socket_path ~= nil then
		if type(config.socket_path) == "string" then
			M.socket_path = config.socket_path
		else
			error("shades.nvim: expected 'socket_path' to be a string in the configuration table.")
		end
	end

	M.listen()
end

return M
