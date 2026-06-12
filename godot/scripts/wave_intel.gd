class_name WaveIntel
## Wave Intelligence math — pure port of JS 03_abilities.js:78-248.

const ORDER: Array[StringName] = [&"basic", &"fast", &"tank", &"splitter", &"bulwark", &"shifter", &"boss"]

## Largest-remainder rounding split (JS distributeByWeights).
static func distribute_by_weights(total: int, weights: Array) -> Dictionary:
	var result := {}
	var used := 0
	var remainders := []
	for w in weights:
		var raw: float = total * w.weight
		var base := int(raw)
		result[w.type] = base
		used += base
		remainders.append({type = w.type, frac = raw - base})
	remainders.sort_custom(func(a, b): return a.frac > b.frac)
	var leftover := total - used
	for i in leftover:
		var item: Dictionary = remainders[i % remainders.size()]
		result[item.type] = int(result.get(item.type, 0)) + 1
	return result

static func predicted_distribution(wave: int) -> Dictionary:
	var base_count := 5 + int(wave * 2.5)
	var dist := {}
	if wave < 3:
		dist[&"basic"] = base_count
	elif wave < 5:
		dist = distribute_by_weights(base_count, [
			{type = &"basic", weight = 0.7}, {type = &"fast", weight = 0.3}])
	elif wave < 10:
		var fixed_tank: int = mini(2, base_count) if wave % 5 == 0 else 0
		dist = distribute_by_weights(base_count - fixed_tank, [
			{type = &"basic", weight = 0.75}, {type = &"fast", weight = 0.2},
			{type = &"tank", weight = 0.05}])
		dist[&"tank"] = int(dist.get(&"tank", 0)) + fixed_tank
	else:
		var weights := [{type = &"basic", weight = 0.3}, {type = &"fast", weight = 0.5},
				{type = &"tank", weight = 0.2}]
		if wave >= 15:
			weights = [{type = &"basic", weight = 0.3}, {type = &"fast", weight = 0.2},
					{type = &"tank", weight = 0.2}, {type = &"splitter", weight = 0.3}]
		if wave >= 20:
			weights = [{type = &"basic", weight = 0.3}, {type = &"fast", weight = 0.2},
					{type = &"tank", weight = 0.2}, {type = &"splitter", weight = 0.15},
					{type = &"bulwark", weight = 0.15}]
		if wave >= 30:
			weights = [{type = &"basic", weight = 0.3}, {type = &"fast", weight = 0.2},
					{type = &"tank", weight = 0.2}, {type = &"splitter", weight = 0.15},
					{type = &"bulwark", weight = 0.07}, {type = &"shifter", weight = 0.08}]
		dist = distribute_by_weights(base_count, weights)
	if wave % 10 == 0:
		dist[&"boss"] = int(dist.get(&"boss", 0)) + 1
	return dist

static func tags(wave: int, upgraded: int, mutated: int, max_tier: int) -> Array:
	var out := []
	if wave % 10 == 0:
		out.append({label = "BOSS", color = C.COL_PINK})
	if wave > 50 and wave % 5 == 0 and wave % 10 != 0:
		out.append({label = "SURPRISE_BOSS", color = Color("ffcc66")})
	if wave >= 20:
		out.append({label = "TAUNT", color = C.COL_YELLOW})
	if wave >= 30:
		out.append({label = "STEALTH", color = Color("ff66cc")})
	if wave % 20 == 0:
		out.append({label = "MUT_EVENT", color = Color.WHITE})
	if mutated > 0:
		out.append({label = "MUTx%d" % mutated, color = Color.WHITE})
	if upgraded > 0:
		out.append({label = "T%d" % max_tier, color = C.COL_BLUE})
	return out

static func report(wave: int, rifts: Array, is_wave_active: bool, live_distribution: Dictionary) -> Dictionary:
	var upgraded := 0
	var mutated := 0
	var max_tier := 1
	for rift in rifts:
		if rift.level > 1:
			upgraded += 1
		if not rift.mutation.is_empty():
			mutated += 1
		max_tier = maxi(max_tier, rift.level)
	var tag_list := tags(wave, upgraded, mutated, max_tier)
	var score := tag_list.size() + (1 if wave >= 50 else 0) + (1 if upgraded > 0 else 0)
	var threat := "CRITICAL" if score >= 7 else ("HIGH" if score >= 5 else ("ELEVATED" if score >= 3 else "NORMAL"))
	var threat_color := C.COL_PINK if threat == "CRITICAL" else (Color("ff7a00") if threat == "HIGH" \
			else (Color("ffcc00") if threat == "ELEVATED" else Color.WHITE))
	var mutation_status: String
	if wave % 20 == 0:
		mutation_status = "MUTATION EVENT THIS WAVE"
	elif mutated > 0:
		mutation_status = "%d ACTIVE MUTATION SECTOR(S)" % mutated
	else:
		mutation_status = "Stable | Next mutation check in %d wave(s)" % (20 - wave % 20)
	return {
		wave = wave, total_rifts = rifts.size(), tags = tag_list, threat = threat,
		threat_color = threat_color, mutation_status = mutation_status,
		distribution = live_distribution if (is_wave_active and not live_distribution.is_empty())
				else predicted_distribution(wave),
	}
