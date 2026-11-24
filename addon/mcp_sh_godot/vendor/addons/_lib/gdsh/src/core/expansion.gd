extends RefCounted
## Expand word fragments into argument values. Output never becomes shell syntax.

const Lexer = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/lexer.gd")
const Context = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/context.gd")
const _Anchor = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/anchor.gd")

static func words(input:Array, ctx:Context, completion:=false) -> Dictionary:
	var values:Array = []
	var metadata:Array = []
	for word in input:
		var expanded = word_values(word, ctx, completion)
		for value in expanded:
			values.append(value)
			metadata.append({"raw": word.raw, "start": word.start, "end": word.end, "quoted": word.quoted, "literal": word.raw.left(1) in ["\"", "'", "\\"]})
	return {"values": values, "metadata": metadata}

static func word_values(word:Dictionary, ctx:Context, completion:=false, scalar:=false, seen:Dictionary={}) -> Array:
	var fields:Array = [""]
	for part in word.parts:
		var value:String = ""
		var split = false
		match part.kind:
			"text": value = part.value
			"variable":
				value = variable(part.value, ctx, completion, seen)
			"substitution":
				if completion:
					value = "$(" + part.value + ")"
				else:
					var child = Context.new_ctx("Substitution", ctx, true)
					var engine = load(_Anchor.path("src/core/execute.gd"))
					# Expansion is synchronous; the engine fails the command if the body pauses.
					if not engine.run_substitution(child, part.get("tree", {}), part.value):
						ctx.data[engine.SUBSTITUTION_FAILED_KEY] = true
					ctx.absorb_error(child.stderr) # The child streamed its own diagnostics live.
					value = Context.plain_text(child.stdout).rstrip("\n")
					split = not part.quoted and not scalar
		if split:
			var pieces = value.replace("\t", " ").replace("\n", " ").split(" ", false)
			if pieces.is_empty(): continue
			fields[-1] += pieces[0]
			for i in range(1, pieces.size()): fields.append(pieces[i])
		else:
			fields[-1] += value
	return fields

static func variable(name:String, ctx:Context, completion:=false, seen:Dictionary={}) -> String:
	var key = name.trim_prefix("$")
	if key.is_valid_int():
		var index = key.to_int()
		if index == 0: return str(ctx.variables.get("$0", ""))
		return str(ctx.positional_args[index - 1]) if index <= ctx.positional_args.size() else ""
	match name:
		"$?": return str(ctx.last_status)
		"$#": return str(ctx.positional_args.size())
		"$@": return " ".join(ctx.positional_args)
	var value = str(ctx.variables.get(name, ""))
	if "$" not in value or seen.has(name): return value
	var next_seen = seen.duplicate()
	next_seen[name] = true
	# Retain GDSh's recursive variable expansion, without interpreting operators.
	var scanned = Lexer.scan(value, true)
	var result = ""
	var end = 0
	for token in scanned.tokens:
		if token.kind == "eof": break
		result += value.substr(end, token.start - end)
		if token.kind == "word":
			result += " ".join(word_values(token, ctx, completion, true, next_seen))
		else:
			result += token.raw
		end = token.end
	return result + value.substr(end)

static func scalar(input:Array, ctx:Context, completion:=false) -> String:
	var values:Array = []
	for word in input:
		values.append("".join(word_values(word, ctx, completion, true)))
	return " ".join(values)

