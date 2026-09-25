local M = {}

M.set_color = nil
M.socket_path = "/tmp/theme-change.sock"
M.current_theme = nil
M.current_palette = nil
M._theme_callbacks = {}
-- set once the daemon can't be reached, so wait() gives up at once instead of
-- sitting out its whole timeout
M._unreachable = false

-- the libuv callbacks run in a fast event context, where vim.notify throws E5560
local function notify(message, level)
	vim.schedule(function()
		vim.notify("shades.nvim: " .. message, level)
	end)
end

local RETRY_MIN_MS = 1000
local RETRY_MAX_MS = 30000
local retry_delay_ms = RETRY_MIN_MS
local retry_timer = vim.loop.new_timer()
-- notify once per outage rather than on every failed retry
local outage_notified = false

-- close the dead pipe and try listen() again after a backoff, so a daemon that
-- restarts, or starts after Neovim, is picked up without restarting Neovim
local function reconnect_later(pipe, message)
	if not pipe:is_closing() then
		pipe:close()
	end
	M._unreachable = true

	if not outage_notified then
		outage_notified = true
		notify(message .. ", retrying", vim.log.levels.WARN)
	end

	local delay = retry_delay_ms
	retry_delay_ms = math.min(retry_delay_ms * 2, RETRY_MAX_MS)
	retry_timer:start(delay, 0, function()
		M.listen()
	end)
end

-- Function to apply theme (or any other configuration provided by the user)
function M.apply_theme(theme, palette)
	if M.set_color then
		M.set_color(theme, palette)
	end
end

function M.listen()
	local function _process_message(message)
		-- only the first colon delimits the verb; a noun may contain colons of its own
		local verb, noun = message:match("^([^:]+):(.*)$")
		if not verb then
			return
		end

		if verb == "palette" then
			local ok, decoded = pcall(vim.json.decode, noun)
			if ok then
				M.current_palette = decoded
			else
				notify("could not decode palette: " .. tostring(decoded), vim.log.levels.WARN)
			end
		elseif verb == "set" then
			-- pair this set with the palette that preceded it rather than whatever
			-- is current when the scheduled callback finally runs, so two theme
			-- changes in quick succession cannot hand the first one's theme the
			-- second one's colors
			local palette = M.current_palette
			vim.schedule(function()
				M.current_theme = noun
				M.apply_theme(noun, palette)
				-- flush any callbacks waiting on the initial theme
				local callbacks = M._theme_callbacks
				M._theme_callbacks = {}
				for _, cb in ipairs(callbacks) do
					cb(M.current_theme, palette)
				end
			end)
		end
	end

	local pipe, pipe_err = vim.loop.new_pipe(true)
	if pipe_err then
		M._unreachable = true
		notify("error creating pipe: " .. pipe_err, vim.log.levels.ERROR)
		return
	end

	pipe:connect(M.socket_path, function(connect_err)
		if connect_err then
			reconnect_later(pipe, "connection error: " .. connect_err)
			return
		end

		M._unreachable = false
		retry_delay_ms = RETRY_MIN_MS
		if outage_notified then
			outage_notified = false
			notify("reconnected", vim.log.levels.INFO)
		end

		local buffer = ""
		pipe:read_start(function(read_err, data)
			if read_err then
				reconnect_later(pipe, "read error: " .. read_err)
				return
			end

			if not data then
				reconnect_later(pipe, "daemon closed the connection")
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
				notify("write error: " .. write_err, vim.log.levels.ERROR)
			end
		end)
		-- ask for the current theme
		pipe:write("get:\n", function(write_err)
			if write_err then
				notify("write error: " .. write_err, vim.log.levels.ERROR)
			end
		end)
	end)
end

function M.get(callback)
	if M.current_theme then
		callback(M.current_theme, M.current_palette)
	else
		-- theme not yet received from socket; queue until listen() gets the response
		table.insert(M._theme_callbacks, callback)
	end
end

-- Block until the daemon's current theme has been applied, for a startup that
-- wants the real colors on its first frame instead of repainting a moment
-- later. Only a wait on the event loop lets the connect, the read and the
-- scheduled apply run at all during init. Gives up once the daemon is known to
-- be unreachable, or after timeout_ms.
---@param timeout_ms integer
---@return boolean applied
function M.wait(timeout_ms)
	vim.wait(timeout_ms, function()
		return M.current_theme ~= nil or M._unreachable
	end, 1)
	return M.current_theme ~= nil
end

-- The colors of the current theme, keyed by shades' names (BG0, FG, RED, ...).
-- nil until the first palette arrives, and nil forever against a daemon too old
-- to send one.
function M.palette()
	return M.current_palette
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
