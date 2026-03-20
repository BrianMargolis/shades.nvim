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
		local parts = vim.split(message, ":")
		local verb = parts[1]
		local noun = parts[2]

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

	local socket_path = "/tmp/theme-change.sock"

	local uv = vim.loop
	local pipe, pipe_err = vim.loop.new_pipe(true)
	if pipe_err then
		print("Error creating pipe:", pipe_err)
		return
	end

	pipe:connect(socket_path, function(connect_err)
		if connect_err then
			print("Connection error:", connect_err)
			return
		end

		local buffer = ""
		pipe:read_start(function(read_err, data)
			if read_err then
				print("Read error:", read_err)
				return
			end

			if data then
				-- trim whitespace
				data = string.gsub(data, "%s+", "")

				-- put it on the buffer
				buffer = buffer .. data

				-- split it up, in case we got multiple messages
				local parts = vim.split(buffer, "\n")

				if #parts == 1 then
					_process_message(parts[1])
					buffer = ""
				else
					for i, part in ipairs(parts) do
						if i < #parts then
							_process_message(part)
						end
					end

					buffer = parts[#parts]
				end
			else
				print("Received nil")
			end
		end)

		-- write the subscribe message in
		pipe:write("subscribe:neovim\n", function(write_err)
			if write_err then
				print("Write error:", write_err)
				return
			end
		end)
		-- ask for the current theme
		pipe:write("get:\n", function(write_err)
			if write_err then
				print("Write error:", write_err)
				return
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
	vim.notify("Setting up shades with provided configuration", vim.log.levels.WARN)
	if type(config) ~= "table" then
		error("Invalid configuration table provided.")
	end

	if type(config.set_color) == "function" then
		M.set_color = config.set_color
	else
		error("Expected 'set_color' to be a function in the configuration table.")
	end

	if type(config.socket_path) == "string" then
		M.socket_path = config.socket_path
	else
		error("Expected 'socket_path' to be a string in the configuration table.")
	end

	M.listen()
end

return M
