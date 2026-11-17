extends RefCounted
## Lossless lexical tokens. Words contain fragments, never expanded command text.

var source:String
var pos:int = 0
var tolerant:bool = false
var error:Dictionary = {}
var _nesting:int = 0
var raw_commands:Array[String] = []

static func scan(text:String, incomplete:=false, raw_names:Array[String]=[]) -> Dictionary:
	var lexer = new()
	lexer.source = text
	lexer.tolerant = incomplete
	lexer.raw_commands = raw_names
	var tokens = lexer._scan(false)
	return {"tokens": tokens, "error": lexer.error, "source": text}

func _scan(in_substitution:bool) -> Array:
	var tokens:Array = []
	var parens = 0
	var command_start = true
	var raw_active = false
	var redirect_target = false
	while pos < source.length() and error.is_empty():
		var ch = source[pos]
		if ch in [" ", "\t", "\r"]:
			pos += 1
			continue
		if ch == "#":
			while pos < source.length() and source[pos] != "\n":
				pos += 1
			continue
		if ch == "\\" and source.substr(pos, 2) == "\\\n":
			pos += 2
			continue
		if in_substitution and ch == ")" and parens == 0:
			break
		var start = pos
		var op = ""
		# A descriptor is recognized only immediately before a redirection operator.
		if ch >= "0" and ch <= "9":
			var end = pos
			while end < source.length() and source[end] >= "0" and source[end] <= "9":
				end += 1
			if source.substr(end, 1) in [">", "<"]:
				pos = end
		for candidate in ["&>>", ">>&", "&&", "||", "|&", ">>", "<<", ">&", "<&", "&>", ">", "<", "|", "&", ";", "\n", "{", "}", "(", ")"]:
			if source.substr(pos, candidate.length()) == candidate:
				op = candidate
				break
		if op != "":
			pos += op.length()
			var kind = "redirect" if ">" in op or "<" in op else op
			if op == "(": parens += 1
			if op == ")": parens -= 1
			tokens.append(_token(kind, start, pos))
			if kind == "redirect":
				redirect_target = true
			else:
				command_start = kind in [";", "\n", "|", "&&", "||", "{", "("]
				raw_active = false
				redirect_target = false
		else:
			pos = start
			if raw_active and not redirect_target:
				tokens.append(_raw_arguments())
				continue
			var word = _word()
			tokens.append(word)
			if redirect_target:
				redirect_target = false
				continue
			if command_start and not word.quoted and word.raw in raw_commands:
				raw_active = true
				tokens.append(_raw_arguments())
			command_start = command_start and word.raw in ["if", "elif", "while"]
	tokens.append(_token("eof", pos, pos))
	return tokens

## A host raw command owns its arguments, but not outer GDSh operators.
## Quotes and balanced groups are opaque to the GDSh word grammar.
func _raw_arguments() -> Dictionary:
	while pos < source.length() and source[pos] in [" ", "\t"]: pos += 1
	var start = pos
	_raw_span("")
	return _token("raw_args", start, pos)


## Scan raw source through `close`. An empty `close` is the argument list itself,
## which instead stops before an outer GDSh operator.
func _raw_span(close:String) -> void:
	var start = pos
	_nesting += 1
	if _nesting > 128:
		_fail("Raw argument nesting limit exceeded", start)
		return
	var quote = ""
	while pos < source.length() and error.is_empty():
		var ch = source[pos]
		if ch == "\\" and quote != "'":
			pos = mini(pos + 2, source.length())
			continue
		var substitution = quote != "'" and ch == "$" and source.substr(pos + 1, 1) in ["(", "{"]
		var group = quote.is_empty() and (ch == "(" or ch == "{" and not close.is_empty())
		if substitution or group:
			if substitution: pos += 1
			var opener = source[pos]
			pos += 1
			_raw_span(")" if opener == "(" else "}")
			continue
		if not quote.is_empty():
			if ch == quote: quote = ""
		elif ch in ["'", '"']:
			quote = ch
		elif ch == close:
			pos += 1
			_nesting -= 1
			return
		elif close.is_empty() and _raw_stop(ch, start):
			break
		pos += 1
	_nesting -= 1
	if tolerant or not error.is_empty(): return
	if not close.is_empty(): _fail("Unclosed raw argument group", start)
	elif not quote.is_empty(): _fail("Unclosed raw command argument", start)


func _raw_stop(ch:String, start:int) -> bool:
	if ch in [";", "\n", "|", "&", ">", "<", "{", "}", ")"]: return true
	if pos != start and not source[pos - 1] in [" ", "\t"]: return false
	if ch == "#": return true
	if not ch.is_valid_int(): return false
	var end = pos
	while end < source.length() and source[end].is_valid_int(): end += 1
	return source.substr(end, 1) in [">", "<"]


func _token(kind:String, start:int, end:int) -> Dictionary:
	return {"kind": kind, "start": start, "end": end, "raw": source.substr(start, end - start)}

func _word() -> Dictionary:
	var start = pos
	var parts:Array = []
	var quoted = false
	while pos < source.length() and error.is_empty():
		var ch = source[pos]
		if ch in [" ", "\t", "\r", "\n", ";", "|", "&", ">", "<", "{", "}", "(", ")"]:
			break
		if ch in ["'", '"']:
			quoted = true
			_quote(parts, ch)
		elif ch == "\\":
			quoted = true
			_escape(parts, false)
		elif ch == "$":
			_dollar(parts, false)
		else:
			_text(parts, ch, false)
			pos += 1
	var token = _token("word", start, pos)
	token.parts = parts
	token.quoted = quoted
	return token

func _quote(parts:Array, quote:String):
	var start = pos
	pos += 1
	# An empty quoted fragment still represents an argument.
	parts.append({"kind": "text", "value": "", "quoted": true})
	while pos < source.length() and error.is_empty():
		var ch = source[pos]
		if ch == quote:
			pos += 1
			return
		if quote == '"' and ch == "$":
			_dollar(parts, true)
		elif quote == '"' and ch == "\\":
			_escape(parts, true)
		else:
			_text(parts, ch, true)
			pos += 1
	if not tolerant:
		_fail("Unclosed quote", start)

func _escape(parts:Array, quoted:bool):
	var start = pos
	pos += 1
	if pos == source.length():
		if not tolerant: _fail("Incomplete escape", start)
		return
	var ch = source[pos]
	if ch != "\n":
		if quoted and not ch in ["$", '"', "\\"]:
			_text(parts, "\\", true)
		_text(parts, ch, true)
	pos += 1

func _dollar(parts:Array, quoted:bool):
	var start = pos
	pos += 1
	if source.substr(pos, 1) == "(":
		pos += 1
		_nesting += 1
		if _nesting > 128:
			_fail("Substitution nesting limit exceeded", start)
			return
		var body_start = pos
		var tokens = _scan(true)
		var body_end = pos
		var closed = source.substr(pos, 1) == ")"
		if closed:
			pos += 1
		elif not tolerant:
			_fail("Unclosed command substitution", start)
		_nesting -= 1
		parts.append({"kind": "substitution", "tokens": tokens, "value": source.substr(body_start, body_end - body_start), "start": start, "end": pos, "quoted": quoted, "closed": closed})
		return
	if source.substr(pos, 1) == "{":
		_braced_variable(parts, quoted, start)
		return
	var name_start = pos
	if source.substr(pos, 1) in ["?", "#", "@"]:
		pos += 1
	else:
		while pos < source.length() and _identifier_char(source[pos]):
			pos += 1
	if pos == name_start:
		_text(parts, "$", quoted)
	else:
		parts.append({"kind": "variable", "value": source.substr(start, pos - start), "quoted": quoted, "start": start, "end": pos})

## `${name}` joins a variable with following text. The part keeps the plain `$name` value,
## so expansion and highlighting treat it like `$name` over the braced span.
func _braced_variable(parts:Array, quoted:bool, start:int):
	var brace = pos
	pos += 1
	var name_start = pos
	if source.substr(pos, 1) in ["?", "#", "@"]:
		pos += 1
	else:
		while pos < source.length() and _identifier_char(source[pos]):
			pos += 1
	var name = source.substr(name_start, pos - name_start)
	if name != "" and source.substr(pos, 1) == "}":
		pos += 1
		parts.append({"kind": "variable", "value": "$" + name, "quoted": quoted, "start": start, "end": pos})
		return
	if not tolerant:
		_fail("Bad substitution", start)
		return
	# Completion and highlighting: keep a partly typed ${...} together as one variable span.
	if source.substr(pos, 1) == "}":
		pos += 1
		parts.append({"kind": "variable", "value": "$" + name, "quoted": quoted, "start": start, "end": pos})
	elif pos == source.length():
		parts.append({"kind": "variable", "value": "$" + name, "quoted": quoted, "start": start, "end": pos})
	else:
		pos = brace + 1
		_text(parts, "${", quoted)

static func _identifier_char(ch:String) -> bool:
	return ch == "_" or ch >= "a" and ch <= "z" or ch >= "A" and ch <= "Z" or ch >= "0" and ch <= "9"

static func _text(parts:Array, value:String, quoted:bool):
	if not parts.is_empty() and parts.back().kind == "text" and parts.back().quoted == quoted:
		parts.back().value += value
	else:
		parts.append({"kind": "text", "value": value, "quoted": quoted})

func _fail(message:String, offset:int):
	if error.is_empty():
		error = diagnostic(source, message, offset)

static func diagnostic(text:String, message:String, offset:int) -> Dictionary:
	var before = text.left(offset)
	return {"message": message, "offset": offset, "line": before.count("\n") + 1, "column": offset - before.rfind("\n")}

static func literal(value:String, start:=0, end:=-1) -> Dictionary:
	return {"kind": "word", "raw": value, "start": start, "end": start + value.length() if end < 0 else end, "quoted": false, "parts": [{"kind": "text", "value": value, "quoted": false}]}

static func literal_value(word:Dictionary) -> Variant:
	var value = ""
	for part in word.get("parts", []):
		if part.kind != "text": return null
		value += part.value
	return value

