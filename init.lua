-- Backwards compatibility for 0.4.x
if not core.register_on_receiving_chat_message then
	core.register_on_receiving_chat_message = core.register_on_receiving_chat_messages
end

local color_reset = "\x1b(c@#FFF)"
local c_pattern = "\x1b%(c@#?[0-9a-fA-F]+%)"
local c_namepat = "[A-z0-9-_]+"

local function tokenize(s)
	local tokens = {}

	local i = 1
	local j = 1

	while true do
		if s:sub(j, j) == "" then
			if i < j then
				table.insert(tokens, s:sub(i, j - 1))
			end
			return tokens

		elseif s:sub(j, j):byte() == 27 then
			if i < j then
				table.insert(tokens, s:sub(i, j - 1))
			end

			i = j
			local n = s:sub(i + 1, i + 1)

			if n == "(" then
				local m = s:sub(i + 2, i + 2)
				local k = s:find(")", i + 3, true)
				if m == "T" then
					table.insert(tokens, {
						type = "translation",
						domain = s:sub(i + 4, k - 1)
					})

				elseif m == "c" then
					table.insert(tokens, {
						type = "color",
						color = s:sub(i + 4, k - 1),
					})

				elseif m == "b" then
					table.insert(tokens, {
						type = "bgcolor",
						color = s:sub(i + 4, k - 1),
					})

				else
					error(("couldn't parse %s"):format(s))
				end
				i = k + 1
				j = k + 1

			elseif n == "F" then
				table.insert(tokens, {
					type = "start",
				})
				i = j + 2
				j = j + 2

			elseif n == "E" then
				table.insert(tokens, {
					type = "stop",
				})
				i = j + 2
				j = j + 2

			else
				error(("couldn't parse %s"):format(s))
			end

		else
			j = j + 1
		end
	end
end

local function parse(tokens, i, parsed)
	parsed = parsed or {}
	i = i or 1
	while i <= #tokens do
		local token = tokens[i]
		if type(token) == "string" then
			table.insert(parsed, token)
			i = i + 1

		elseif token.type == "color" or token.type == "bgcolor" then
			table.insert(parsed, token)
			i = i + 1

		elseif token.type == "translation" then
			local contents = {
				type = "translation",
				domain = token.domain
			}
			i = i + 1
			contents, i = parse(tokens, i, contents)
			table.insert(parsed, contents)

		elseif token.type == "start" then
			local contents = {
				type = "escape",
			}
			i = i + 1
			contents, i = parse(tokens, i, contents)
			table.insert(parsed, contents)

		elseif token.type == "stop" then
			i = i + 1
			return parsed, i

		else
			error(("couldn't parse %s"):format(dump(token)))
		end
	end
	return parsed, i
end

local function unparse(parsed, parts)
	parts = parts or {}
	for _, part in ipairs(parsed) do
		if type(part) == "string" then
			table.insert(parts, part)

		else
			if part.type == "bgcolor" then
				table.insert(parts, ("\27(b@%s)"):format(part.color))

			elseif part.type == "color" then
				table.insert(parts, ("\27(c@%s)"):format(part.color))

			elseif part.domain then
				--table.insert(parts, ("\27(T@%s)"):format(part.domain))
				unparse(part, parts)
				--table.insert(parts, "\27E")

			else
				--table.insert(parts, "\27F")
				unparse(part, parts)
				--table.insert(parts, "\27E")

			end
		end
	end

	return parts
end

local function strip_translation(line)
	local tokens = tokenize(line)
	local parsed = parse(tokens)
	return table.concat(unparse(parsed), "")
end

core.register_on_receiving_chat_message(function(line)
	local myname_l = "~[CAPS£"
	if core.localplayer then
		myname_l = core.localplayer:get_name():lower()
	end

	line = strip_translation(line)

	-- Detect color to still do the name mentioning effect
	local color, line_nc = line:match("^(" .. c_pattern .. ")(.*)")
	line = line_nc or line

	local prefix
	local chat_line = false

	local name, color_end, message = line:match("^%<(" .. c_namepat .. ")%>%s*(" .. c_pattern .. ")%s*(.*)")
	if not message then
		name, message = line:match("^%<(" .. c_namepat .. ")%> (.*)")
		if name then
			name = name:gsub(c_pattern, "")
		end
	end

	if message then
		-- To keep the <Name> notation
		chat_line = true
	else
		-- Translated server messages, actions
		prefix, name, message = line:match("^(.*\x1bF)(".. c_namepat .. ")(\x1bE.*)")
	end
	if not message then
		-- Server messages, actions
		prefix, name, message = line:match("^(%*+ )(" .. c_namepat .. ") (.*)")
	end
	if not message then
		-- Colored prefix
		prefix, name, message = line:match("^(.* )%<(" .. c_namepat .. ")%> (.*)")
		if color and message and prefix:len() > 0 then
			prefix = color .. prefix .. color_reset
			color = nil
		end
		chat_line = true
	end
	if not message then
		-- Skip unknown chat line
		return
	end

	prefix = prefix or ""
	local name_wrap = name

	-- No color yet? We need color.
	if not color then
		local color = core.sha1(name, true)
		local R = color:byte( 1) % 0x10
		local G = color:byte(10) % 0x10
		local B = color:byte(20) % 0x10
		if R + G + B < 24 then
			R = 15 - R
			G = 15 - G
			B = 15 - B
		end
		if chat_line then
			name_wrap = "<" .. name .. ">"
		end
		name_wrap = minetest.colorize(string.format("#%X%X%X", R, G, B), name_wrap)
	elseif chat_line then
		name_wrap = "<" .. name .. ">"
	end

	if (chat_line or prefix == "* ") and name:lower() ~= myname_l
			and message:lower():find(myname_l) then
		prefix = minetest.colorize("#F33", "[!] ") .. prefix
	end

	return minetest.display_chat_message(prefix .. (color or "")
		.. name_wrap .. (color_end or "") .. " " .. message)
end)
