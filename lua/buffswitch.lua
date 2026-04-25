local M = {}

M.config = {
	search = true,
	prefix = ">", -- |  | 󰍟 | 
	position = "top", -- top | center
	border = "rounded", -- "single" | "double" | "rounded" | "shadow" | custom: { "┏","━","┓","┃","┛","━","┗","┃" }
	border_hl = "Function",

	keys = {
		forward = {
			"<Down>",
			"<Tab>",
		},
		backward = {
			"<Up>",
			"<S-Tab>",
		},
	},
}

local wins = {}

vim.api.nvim_create_autocmd("VimResized", {
	callback = function()
		for _, item in pairs(wins) do
			local ui = vim.api.nvim_list_uis()[1]
			local col = math.floor((ui.width - item.width) / 2)
			if vim.api.nvim_win_is_valid(item.win) then
				vim.api.nvim_win_set_config(item.win, {
					relative = "editor",
					col = col,
					row = item.row,
				})
			end
		end
	end,
})

local function set_opts(item, cursorline)
	-- buffer options
	vim.bo[item.buf].modifiable = true
	vim.bo[item.buf].bufhidden = "wipe"

	-- window options
	vim.wo[item.win].cursorline = cursorline
	vim.wo[item.win].number = false
	vim.wo[item.win].relativenumber = false
	vim.wo[item.win].signcolumn = "no"
	vim.wo[item.win].cursorcolumn = false
	vim.wo[item.win].winhl =
		string.format("NormalFloat:Normal,FloatBorder:%s,Search:None,IncSearch:None,CurSearch:None", M.config.border_hl)
end

-- safely load devicons
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local function create_win(width, height, row, col, cursorline)
	local buf = vim.api.nvim_create_buf(false, true)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = M.config.border,
	})

	local item = {
		buf = buf,
		win = win,
		row = row,
		width = width,
	}

	set_opts(item, cursorline)

	return item
end

local function get_buffers()
	local result = {}

	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
			local full = vim.api.nvim_buf_get_name(b)
			local name = full ~= "" and vim.fn.fnamemodify(full, ":t") or "[No Name]"

			local icon, hl = "", ""
			if has_devicons then
				local ext = vim.fn.fnamemodify(name, ":e")
				icon, hl = devicons.get_icon(name, ext, { default = true })
			end

			table.insert(result, {
				bufnr = b,
				name = name,
				icon = icon or "?",
				hl = hl,
			})
		end
	end

	return result
end

local function open()
	local current_buf = vim.api.nvim_get_current_buf()
	local origin_win = vim.api.nvim_get_current_win()
	local buffers = get_buffers()
	if #buffers == 0 then
		return
	end

	local filtered = vim.deepcopy(buffers)

	local width = 40
	local height = math.min(#buffers, 15)

	local ui = vim.api.nvim_list_uis()[1]
	local col = math.floor((ui.width - width) / 2)
	local row

	if M.config.position == "top" then
		row = 1
	elseif M.config.position == "center" then
		row = math.floor((ui.height - height) / 2)
	end

	wins.list = create_win(width, height, row, col, true)
	local list = wins.list
	local input = wins.input

	if M.config.search then
		wins.input = create_win(width, 1, height + row + 2, col, false)
		input = wins.input
		vim.bo[input.buf].buftype = "prompt"
		vim.fn.prompt_setprompt(input.buf, " " .. M.config.prefix .. " ")
		vim.cmd("startinsert")
	end

	------------------[ render buffer list ]-------------------------------

	local function render()
		local ns = vim.api.nvim_create_namespace("icon")

		if #filtered == 0 then
			vim.api.nvim_buf_set_lines(list.buf, 0, -1, false, { "  No buffer found." })
		else
			local lines = {}
			for i, b in ipairs(filtered) do
				lines[i] = string.format("  %s %s", b.icon, b.name)
			end

			vim.api.nvim_buf_set_lines(list.buf, 0, -1, false, lines)

			-- apply icon highlights
			for i, b in ipairs(filtered) do
				local start_col = 2
				local end_col = start_col + vim.fn.strdisplaywidth(b.icon)

				-- highlight icon
				vim.api.nvim_buf_set_extmark(list.buf, ns, i - 1, start_col, {
					end_col = end_col,
					hl_group = b.hl,
				})
			end
		end
	end

	render() -- initial render

	if not M.config.search then
		vim.bo[list.buf].buftype = "prompt"
		vim.bo[list.buf].modifiable = false
	end

	-------------------[ set current cursor ]-------------------------------

	local target_line = 1
	for i, b in ipairs(buffers) do
		if b.bufnr == current_buf then
			target_line = i
			break
		end
	end

	vim.api.nvim_win_set_cursor(list.win, { target_line, 0 })

	----------------------[ close window ]-------------------------------

	local function close()
		for _, item in pairs(wins) do
			if vim.api.nvim_win_is_valid(item.win) then
				vim.api.nvim_win_close(item.win, true)
			end
		end
	end

	-----------------------[ filtering ]-------------------------------

	local function filter(text)
		filtered = {}
		text = text:lower()

		for _, b in ipairs(buffers) do
			if b.name:lower():find(text, 1, true) then
				table.insert(filtered, b)
			end
		end

		render()
		vim.api.nvim_win_set_cursor(list.win, { 1, 0 })
	end

	-----------------------[ move buffer ]-------------------------------

	local function move(delta)
		-- local line = vim.fn.line(".")

		local line = vim.api.nvim_win_get_cursor(list.win)[1]
		local new = line + delta

		if new < 1 then
			new = #filtered
		elseif new > #filtered then
			new = 1
		end

		vim.api.nvim_win_set_cursor(list.win, { new, 0 })
	end

	----------------------[ select buffer ]-------------------------------

	local function select()
		-- local line = vim.fn.line(".")
		local line = vim.api.nvim_win_get_cursor(list.win)[1]
		local target = filtered[line]
		if not target then
			return
		end

		vim.api.nvim_set_current_win(origin_win)
		vim.cmd("buffer " .. target.bufnr)
		close()
	end

	-----------------------[ input handling ]-------------------------------

	if M.config.search then
		vim.api.nvim_buf_attach(input.buf, false, {
			on_lines = function()
				vim.schedule(function()
					if not vim.api.nvim_buf_is_valid(input.buf) then
						return
					end

					local line = vim.api.nvim_buf_get_lines(input.buf, 0, 1, false)[1] or ""
					local prefix = vim.fn.prompt_getprompt(input.buf)
					line = line:sub(#prefix + 1) -- remove the prefix
					filter(line)
				end)
			end,
		})
	end

	local function mouseSelect()
		local pos = vim.fn.getmousepos()

		if input and pos.winid == input.win then
			return
		end

		pcall(vim.api.nvim_win_set_cursor, list.win, { pos.line, 0 })
		select()
	end

	---------------------------[ Keymaps ]-------------------------------

	for _, item in pairs(wins) do
		local opts = { buffer = item.buf }
		-- quit window
		vim.keymap.set("n", "q", close, opts)
		vim.keymap.set("n", "<ESC>", close, opts)
		vim.keymap.set({ "n", "i" }, "<C-q>", close, opts)

		-- select buffer
		vim.keymap.set({ "n", "i" }, "<CR>", select, opts)
		vim.keymap.set({ "n", "i" }, "<LeftMouse>", mouseSelect, opts)

		-- forward cycle
		for _, key in pairs(M.config.keys.forward) do
			vim.keymap.set({ "n", "i" }, key, function()
				move(1)
			end, opts)
		end

		-- backward cycle
		for _, key in pairs(M.config.keys.backward) do
			vim.keymap.set({ "n", "i" }, key, function()
				move(-1)
			end, opts)
		end
	end
end

vim.api.nvim_create_user_command("BuffSwitch", function()
	open()
end, { desc = "Switch Buffer" })

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts)
end

return M
