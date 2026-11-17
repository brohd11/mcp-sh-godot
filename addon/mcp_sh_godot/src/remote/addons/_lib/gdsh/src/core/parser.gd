extends RefCounted
## Recursive-descent grammar: list -> logical chain -> pipeline -> command.
## Nodes and tokens are internal dictionaries; no execution occurs while parsing.

const Lexer = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/lexer.gd")
var source:String
var tokens:Array
var pos:int = 0
var error:Dictionary = {}
var tolerant:bool = false
var completion:Dictionary = {"words": [], "redirect": false, "redirect_op": "", "redirect_word": {}, "start": 0}
var _depth:int = 0
var raw_commands:Array[String] = []

static func parse(text:String, incomplete:=false, raw_names:Array[String]=[]) -> Dictionary:
	var scanned = Lexer.scan(text, incomplete, raw_names)
	if not scanned.error.is_empty():
		return {"tree": {}, "error": scanned.error, "completion": {"words": [], "redirect": false, "redirect_op": "", "redirect_word": {}, "start": 0}}
	return from_tokens(scanned.tokens, text, incomplete, raw_names)

static func from_tokens(input:Array, text:String, incomplete:=false, raw_names:Array[String]=[]) -> Dictionary:
	var parser = new()
	parser.tokens = input
	parser.source = text
	parser.tolerant = incomplete
	parser.raw_commands = raw_names
	var tree = parser._list("eof")
	return {"tree": tree, "error": parser.error, "completion": parser.completion}

func _peek(ahead:=0) -> Dictionary:
	return tokens[mini(pos + ahead, tokens.size() - 1)]

func _take() -> Dictionary:
	var token = _peek()
	if token.kind != "eof": pos += 1
	return token

func _is_word(value:String, ahead:=0) -> bool:
	var token = _peek(ahead)
	return token.kind == "word" and not token.quoted and token.raw == value

func _fail(message:String, token:Dictionary={}):
	if error.is_empty():
		if token.is_empty(): token = _peek()
		if tolerant and token.kind == "eof": return
		error = Lexer.diagnostic(source, message, token.start)

func _expect(kind:String) -> Dictionary:
	if _peek().kind != kind:
		_fail("Expected '%s', got '%s'" % [kind, _peek().raw])
		return _peek()
	return _take()

func _new_completion():
	completion = {"words": [], "redirect": false, "redirect_op": "", "redirect_word": {}, "start": _peek().start}

func _list(stop:String) -> Dictionary:
	_depth += 1
	if _depth > 128:
		_fail("Block nesting limit exceeded")
		_depth -= 1
		return {"kind": "list", "items": []}
	var items:Array = []
	_new_completion()
	while _peek().kind != stop and _peek().kind != "eof" and error.is_empty():
		if _peek().kind in [";", "\n"]:
			_take()
			_new_completion()
			continue
		var before = pos
		var item = _logical(false)
		items.append(item)
		if pos == before: break
		if not _peek().kind in [stop, "eof", ";", "\n"] and not item.get("compound", false):
			_fail("Expected a statement separator")
			break
	_depth -= 1
	return {"kind": "list", "items": items}

func _logical(header:bool) -> Dictionary:
	var first = _pipeline(header)
	var links:Array = []
	var compound = first.get("compound", false)
	while _peek().kind in ["&&", "||"] and error.is_empty():
		var op = _take().kind
		while _peek().kind == "\n": _take()
		var right = _pipeline(header)
		links.append({"op": op, "node": right})
		compound = right.get("compound", false)
	if links.is_empty(): return first
	return {"kind": "logical", "first": first, "links": links, "compound": compound}

func _pipeline(header:bool) -> Dictionary:
	var stages:Array = [_command(header)]
	while _peek().kind == "|" and error.is_empty():
		_take()
		while _peek().kind == "\n": _take()
		stages.append(_command(header))
	if stages.size() == 1: return stages[0]
	return {"kind": "pipeline", "stages": stages, "compound": stages.back().get("compound", false)}

func _command(header:bool) -> Dictionary:
	_depth += 1
	if _depth > 128:
		_fail("Command nesting limit exceeded")
		_depth -= 1
		return {}
	var node = _command_inner(header)
	_depth -= 1
	return node

func _command_inner(header:bool) -> Dictionary:
	var node:Dictionary
	if _is_word("if"):
		node = _conditional()
	elif _is_word("while") or _is_word("for"):
		node = _loop()
	elif _peek().kind == "word" and not _peek().quoted and _peek().raw.is_valid_ascii_identifier() and _peek(1).kind == "(" and _peek(2).kind == ")":
		var name = _take().raw
		_take()
		_take()
		while _peek().kind == "\n": _take()
		var body = _body()
		node = {"kind": "function", "name": name, "body": body.tree, "source": body.source, "compound": true}
		if _peek().kind == "redirect": _fail("Redirection on a function declaration is unsupported")
	elif _peek().kind == "(":
		_take()
		var body = _list(")")
		var close = _expect(")")
		if close.kind != "eof": _new_completion()
		node = {"kind": "subshell", "body": body, "compound": true}
	elif _is_word("else") or _is_word("elif"):
		_fail("Unexpected '%s' without matching if" % _peek().raw)
		node = {"kind": "simple", "words": [], "redirs": []}
	elif _assignment_ahead():
		node = _assignment()
	else:
		return _simple(header)
	node.redirs = []
	while _peek().kind == "redirect" and error.is_empty():
		node.redirs.append(_redirect())
	return node

func _body() -> Dictionary:
	var open = _expect("{")
	var tree = _list("}")
	var close = _expect("}")
	if close.kind != "eof": _new_completion()
	return {"tree": tree, "source": source.substr(open.end, maxi(0, close.start - open.end))}

func _conditional() -> Dictionary:
	_take()
	var branches:Array = []
	var condition = _logical(true)
	while _peek().kind == "\n": _take()
	var body = _body()
	branches.append({"condition": condition, "body": body.tree})
	while error.is_empty():
		var saved = pos
		while _peek().kind == "\n": _take()
		if _is_word("elif"):
			_take()
			condition = _logical(true)
			while _peek().kind == "\n": _take()
			body = _body()
			branches.append({"condition": condition, "body": body.tree})
		elif _is_word("else"):
			_take()
			while _peek().kind == "\n": _take()
			body = _body()
			branches.append({"condition": {}, "body": body.tree})
			break
		else:
			pos = saved
			break
	return {"kind": "if", "branches": branches, "compound": true}

func _loop() -> Dictionary:
	var kind = _take().raw
	var node = {"kind": kind, "compound": true}
	if kind == "for":
		var name = _expect("word")
		if not name.raw.is_valid_ascii_identifier(): _fail("Expected a for-loop variable", name)
		node.name = name.raw
		if not _is_word("in"): _fail("Expected 'in' after loop variable")
		else: _take()
		node.words = []
		while _peek().kind == "word" and error.is_empty():
			node.words.append(_word())
		if node.words.is_empty(): _fail("Expected a for-loop collection")
	else:
		node.condition = _logical(true)
	while _peek().kind == "\n": _take()
	node.body = _body().tree
	return node

func _simple(header:bool) -> Dictionary:
	var node = {"kind": "simple", "words": [], "redirs": [], "start": _peek().start}
	completion = {"words": node.words, "redirect": false, "redirect_op": "", "redirect_word": {}, "start": node.start}
	while not _peek().kind in ["eof", ";", "\n", "|", "&&", "||", "}", ")"] and error.is_empty():
		if header and _peek().kind == "{": break
		if _peek().kind == "raw_args":
			var raw = _take()
			node.raw_args = (str(node.get("raw_args", "")).rstrip(" \t") + " " + raw.raw).strip_edges(true, false)
			completion.redirect = false
			completion.raw_args = node.raw_args
			completion.raw_start = raw.start
		elif _peek().kind == "redirect":
			node.redirs.append(_redirect())
		elif _peek().kind == "word" or _peek().kind == "{" and not node.words.is_empty():
			var word = _word()
			if not node.words.is_empty() and word.start == node.words.back().end:
				node.words.back().raw += word.raw
				node.words.back().parts.append_array(word.parts)
				node.words.back().end = word.end
			else:
				node.words.append(word)
			if completion.start == node.start: completion.redirect = false
		else:
			_fail("Unexpected or unsupported operator '%s'" % _peek().raw)
	if node.words.is_empty(): _fail("Expected a command")
	return node

func _word() -> Dictionary:
	if _peek().kind == "{":
		var start = _take().start
		var depth = 1
		while depth > 0 and _peek().kind != "eof":
			var token = _take()
			if token.kind == "{": depth += 1
			if token.kind == "}": depth -= 1
		if depth > 0: _fail("Unclosed literal brace")
		var end = tokens[maxi(0, pos - 1)].end
		return Lexer.literal(source.substr(start, end - start), start, end)
	var word = _expect("word").duplicate(true)
	for part in word.get("parts", []):
		if part.kind == "substitution":
			var nested = from_tokens(part.tokens, source, tolerant, raw_commands)
			part.tree = nested.tree
			if not nested.error.is_empty(): error = nested.error
			if tolerant and not part.closed:
				completion = nested.completion
	return word

func _redirect() -> Dictionary:
	var op = _take()
	if not op.raw in ["<", "0<", ">", "1>", ">>", "1>>", "2>", "2>>", "&>", "&>>"]:
		_fail("Unsupported redirection '%s'" % op.raw, op)
	var target = Lexer.literal("", _peek().start, _peek().end)
	if _peek().kind == "word":
		target = _word()
	else:
		_expect("word")
	var nested_completion = false
	for part in target.get("parts", []):
		if part.kind == "substitution" and not part.get("closed", true):
			nested_completion = true
			break
	if not nested_completion:
		completion.redirect = true
		completion.redirect_op = op.raw
		completion.redirect_word = target
	return {
		"op": op.raw,
		"target": target,
		"stdin": op.raw in ["<", "0<"],
		"stdout": op.raw in [">", "1>", ">>", "1>>", "&>", "&>>"],
		"stderr": op.raw in ["2>", "2>>", "&>", "&>>"],
		"append": op.raw in [">>", "1>>", "2>>", "&>>"],
	}

func _assignment_ahead() -> bool:
	var i = 1 if _is_word("local") or _is_word("alias") else 0
	var word = _peek(i)
	if word.kind != "word": return false
	var name = word.raw.get_slice("=", 0)
	if i == 1 and _is_word("alias"): name = name.trim_prefix("@")
	if not name.is_valid_ascii_identifier(): return false
	return "=" in word.raw or _is_word("=", i + 1)

func _assignment() -> Dictionary:
	var is_alias = _is_word("alias")
	var is_local = _is_word("local")
	if is_alias or is_local: _take()
	var first = _take()
	var name = first.raw.get_slice("=", 0)
	var start = first.start + first.raw.find("=") + 1
	if not "=" in first.raw:
		start = _take().end
	var end = first.end
	var braces = 0
	var parens = 0
	while _peek().kind != "eof" and error.is_empty():
		var kind = _peek().kind
		if braces == 0 and parens == 0:
			if kind in [";", "\n", "}", ")"]: break
			if not is_alias and kind in ["|", "&&", "||", "redirect"]: break
			if kind in ["&", "|&"]:
				_fail("Unsupported operator '%s'" % _peek().raw)
				break
		var token = _take()
		if kind == "{": braces += 1
		if kind == "}": braces -= 1
		if kind == "(": parens += 1
		if kind == ")": parens -= 1
		end = token.end
	if braces != 0 or parens != 0: _fail("Unclosed assignment value")
	end = maxi(start, end)
	var value = source.substr(start, end - start).strip_edges()
	var scanned = Lexer.scan(value, tolerant, raw_commands)
	# An assignment is a scalar: preserve source spacing and punctuation while
	# expanding quote-aware fragments, without joining and reparsing arguments.
	var scalar = Lexer.literal(value)
	scalar.parts = []
	var offset = 0
	for token in scanned.tokens:
		if token.kind == "eof": break
		if token.start > offset:
			scalar.parts.append({"kind": "text", "value": value.substr(offset, token.start - offset), "quoted": false})
		if token.kind == "word": scalar.parts.append_array(token.parts)
		else: scalar.parts.append({"kind": "text", "value": token.raw, "quoted": false})
		offset = token.end
	var words:Array = [scalar]
	if not scanned.error.is_empty(): _fail(scanned.error.message, first)
	# Validate substitution bodies before executing any of the submitted script.
	for word in words:
		for part in word.parts:
			if part.kind == "substitution":
				var nested = from_tokens(part.tokens, value, tolerant, raw_commands)
				part.tree = nested.tree
				if not nested.error.is_empty(): _fail(nested.error.message, first)
	return {"kind": "alias" if is_alias else "assignment", "name": name, "local": is_local, "words": words, "source": value}

