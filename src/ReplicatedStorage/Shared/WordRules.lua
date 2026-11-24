-- Pure word helpers shared by server and client.
local WordRules = {}

function WordRules.Normalize(text)
	if type(text) ~= "string" then
		return nil
	end
	local w = string.lower((text:gsub("%s", "")))
	if #w < 2 or #w > 10 or w:find("[^a-z]") then
		return nil
	end
	return w
end

-- returns number of differing positions and list of changed indices (same length only)
function WordRules.Diff(a, b)
	if #a ~= #b then
		return math.huge, {}
	end
	local changed = {}
	for i = 1, #a do
		if a:sub(i, i) ~= b:sub(i, i) then
			table.insert(changed, i)
		end
	end
	return #changed, changed
end

-- Duel scoring: letters kept in the same spot, plus letters added on the end.
-- CAT -> CATER = 3 kept + 2 added = 5; TREAD -> STEAL = 2; CATER -> CAT = 3.
-- Returns kept, points. A move is legal only if kept >= 1.
function WordRules.Points(prev, w)
	local kept = 0
	for i = 1, math.min(#prev, #w) do
		if prev:sub(i, i) == w:sub(i, i) then
			kept += 1
		end
	end
	return kept, kept + math.max(0, #w - #prev)
end

-- Vowel / consonant helpers
local VOWELS = { a = true, e = true, i = true, o = true, u = true }
local function isConsonant(ch)
	return ch:match("[a-z]") and not VOWELS[ch]
end

----------------------------------------------------------------
-- Inflection check (base -> derived):
-- Plural / past tense only: cats, boxes, baked, jumped, y-to-ies/ied, doubled consonants
----------------------------------------------------------------
local function inflectsForward(base, derived)
	-- standard plural / past tense: cats, boxes, baked, jumped
	if derived == base .. "s" or derived == base .. "es" or derived == base .. "d" or derived == base .. "ed" then
		return true
	end
	-- y -> ies / ied: try -> tries / tried
	if base:sub(-1) == "y" and #base >= 2 then
		local stem = base:sub(1, -2)
		if derived == stem .. "ies" or derived == stem .. "ied" then
			return true
		end
	end
	-- doubled final consonant + ed: stop -> stopped
	if #base >= 2 and isConsonant(base:sub(-1)) then
		if derived == base .. base:sub(-1) .. "ed" then
			return true
		end
	end
	return false
end

-- Plural/past-tense stems, to catch switching forms of one word (settles <-> settled, jumps <-> jumped)
local function candidateStems(w)
	local stems = { [w] = true }
	local len = #w
	if len <= 3 then
		return stems
	end
	-- ends in 's' (settles -> settle, cats -> cat, boxes -> box, tries -> try)
	if w:sub(-1) == "s" then
		stems[w:sub(1, -2)] = true
		if w:sub(-2) == "es" and len >= 4 then
			stems[w:sub(1, -3)] = true
		end
		if w:sub(-3) == "ies" and len >= 4 then
			stems[w:sub(1, -4) .. "y"] = true
		end
	end
	-- ends in 'd' (settled -> settle, baked -> bake, jumped -> jump, stopped -> stop, tried -> try)
	if w:sub(-1) == "d" then
		if w:sub(-2) == "ed" and len >= 4 then
			stems[w:sub(1, -2)] = true
			stems[w:sub(1, -3)] = true
			stems[w:sub(1, -3) .. "e"] = true
			if len >= 5 and isConsonant(w:sub(-3, -3)) and w:sub(-3, -3) == w:sub(-4, -4) then
				stems[w:sub(1, -4)] = true
			end
		end
		if w:sub(-3) == "ied" and len >= 4 then
			stems[w:sub(1, -4) .. "y"] = true
		end
	end
	return stems
end

function WordRules.SharesStem(a, b)
	if a == b then
		return true
	end
	local stemsA = candidateStems(a)
	local stemsB = candidateStems(b)
	for sA in pairs(stemsA) do
		if #sA >= 3 and stemsB[sA] then
			return true
		end
	end
	return false
end

-- Bidirectional inflection check: base -> derived OR derived -> base OR shared stem (settles <-> settled)
function WordRules.IsInflection(prev, w)
	return inflectsForward(prev, w) or inflectsForward(w, prev) or WordRules.SharesStem(prev, w)
end

function WordRules.IsRare(word, rareLetters)
	for i = 1, #word do
		if rareLetters[word:sub(i, i)] then
			return true
		end
	end
	return false
end

return WordRules
