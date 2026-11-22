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
-- Regular plural/past/continuous: cats, boxes, baked, jumped, -ing, y-to-ies/ied, doubled consonants
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
	-- silent-e drop: humble -> humbled / humbling, dance -> danced / dancer
	if base:sub(-1) == "e" and #base >= 3 then
		local stem = base:sub(1, -2)
		if derived == stem .. "ed" or derived == stem .. "ing" or derived == stem .. "er" or derived == stem .. "ers" then
			return true
		end
	end
	return false
end

-- Extract candidate stems/roots for a word to detect tense/plural/derivation switching
-- (e.g. settles <-> settled, danced <-> dancing, jumped <-> jumps)
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
		stems[w:sub(1, -2)] = true
		if w:sub(-2) == "ed" and len >= 4 then
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
	-- ends in 'ing' (settling -> settle, jumping -> jump, dancing -> dance, stopping -> stop)
	if len >= 5 and w:sub(-3) == "ing" then
		stems[w:sub(1, -4)] = true
		stems[w:sub(1, -4) .. "e"] = true
		if len >= 6 and isConsonant(w:sub(-4, -4)) and w:sub(-4, -4) == w:sub(-5, -5) then
			stems[w:sub(1, -5)] = true
		end
	end
	-- ends in 'er' (dancer -> dance, jumper -> jump, runner -> run)
	if len >= 4 and w:sub(-2) == "er" then
		stems[w:sub(1, -3)] = true
		stems[w:sub(1, -3) .. "e"] = true
		if len >= 5 and isConsonant(w:sub(-3, -3)) and w:sub(-3, -3) == w:sub(-4, -4) then
			stems[w:sub(1, -4)] = true
		end
	end
	-- ends in 'ers' (dancers -> dance, runners -> run)
	if len >= 5 and w:sub(-3) == "ers" then
		stems[w:sub(1, -4)] = true
		stems[w:sub(1, -4) .. "e"] = true
		if len >= 6 and isConsonant(w:sub(-4, -4)) and w:sub(-4, -4) == w:sub(-5, -5) then
			stems[w:sub(1, -5)] = true
		end
	end
	-- ends in 'ly' (quickly -> quick, happily -> happy)
	if len >= 4 and w:sub(-2) == "ly" then
		stems[w:sub(1, -3)] = true
		if len >= 5 and w:sub(-3) == "ily" then
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

----------------------------------------------------------------
-- Suffix manipulation ban: blocks lazy tense/derivation moves
-- (e.g., dance <-> dancer, jacker <-> jackers, quick <-> quickly, profession <-> professional).
-- Only blocks grammatical tenses/plurals and direct derivational forms (-ing, -ers, -er, -ed, -es, -ly, -al, -s, -d).
-- Does NOT block natural vocabulary changes like rat -> ratty.
----------------------------------------------------------------

local SUFFIXES = {
	"ing", "ers", "er", "ed", "es", "ly", "al", "s", "d",
}

-- Check if `derived` is `base` + one suffix (handling spelling transformations)
local function suffixForward(base, derived)
	if #derived <= #base then
		return false
	end
	for _, sfx in ipairs(SUFFIXES) do
		-- direct append: profession + al = professional, jacker + s = jackers
		if derived == base .. sfx then
			return true
		end
		-- silent-e drop: dance + ing = dancing, dance + er = dancer, humble + ing = humbling
		if base:sub(-1) == "e" and VOWELS[sfx:sub(1, 1)] then
			if derived == base:sub(1, -2) .. sfx then
				return true
			end
		end
		-- consonant doubling: run + ing = running, stop + ed = stopped
		if #base >= 2 and isConsonant(base:sub(-1)) then
			if derived == base .. base:sub(-1) .. sfx then
				return true
			end
		end
		-- y -> i conversion: happy -> happily, baby -> babies
		if base:sub(-1) == "y" and #base >= 2 then
			local stem = base:sub(1, -2)
			if derived == stem .. "i" .. sfx then
				return true
			end
			if sfx == "s" and derived == stem .. "ies" then
				return true
			end
		end
	end
	return false
end

-- Bidirectional: is the move just adding OR removing a suffix?
function WordRules.IsSuffixManipulation(prev, w)
	return suffixForward(prev, w) or suffixForward(w, prev)
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
