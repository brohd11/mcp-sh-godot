extends RefCounted

const PRINT_DEBUG = false
const NO_MATCHING_COMMAND = &"__no_matching_command__"
const FUNCTION_KEY = "__function__"
const RETURN_KEY = "__function_return__"

enum ExitCode { OK, FAIL, ERR }
enum FlagType { NONE, FILE, DIR, CLASS, USER_CLASS }

class ScopeDataKeys:
	const SCRIPT = &"script"

class Colors:
	const SYMBOL = Color(0.975, 0.703, 0.585)
	const SCOPE = Color.SKY_BLUE

