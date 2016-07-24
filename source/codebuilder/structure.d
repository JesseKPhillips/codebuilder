/**
 * Provides common functions during language conversion.
 */
module codebuilder.structure;

import std.algorithm;
import std.conv;
import std.range;
import std.regex;

string indentation = "\t";
unittest {
	auto code = CodeBuilder(1);
	code.modifyLine = false;
	scope(exit) indentation = "\t";
	indentation = "    ";
	code.put("Hello");
	assert(code.finalize().startsWith("    "));
}

/*
 * Converts a numeric to an indent string
 */
string indented(int indentCount) {
    assert(indentCount > -1, "Indentation can never be less than 0.");
    return to!(string)(repeat(indentation, indentCount).join.array);
}

/**
 * Specifies how indentation should be applied to this line.
 *
 * open - specifies that this opens a block and should indent
 * future lines.
 *
 * close - specifies that this closes a block, itself and
 * future lines should indent one less.
 *
 * none - perform not modification to the indentation.
 */
enum Indent { none, open, close = 4 }

struct Memory {
	private CodeBuilder.Operation[][string] saved;
}

/**
 * An output range that provides extended functionality for
 * constructing a well formatted string of code.
 *
 * CodeBuilder has three main operations.
 *
 * $(UL
 *    $(LI put - Applies string directly to desired output)
 *    $(LI push - Stacks string for later)
 *    $(LI build - Constructs a sequence of strings)
 * )
 *
 * $(H1 put)
 *
 * The main operation for placing code into the buffer. This will sequentially
 * place code into the buffer. Similar operations are provided for the other
 * operations.
 *
 * $(D rawPut) will place the string without indentation added.
 *
 * One can place the current indentation level without code by calling put("");
 *
 * $(H1 push)
 *
 * This places code onto a stack. $(B pop) can be used to put the code into the
 * buffer.
 *
 * $(H1 build)
 *
 * Building code in a sequence can be pushed onto the stack, or saved to be put
 * into the buffer later.
 */
struct CodeBuilder {
	struct Operation {
		string text;
		Indent indent;
		bool raw;
		string file;
		int line;
	}
	private string upper;
	private Operation[][] lower;
	private Operation[] store;
	private Operation[][string] saved;

	int indentCount;
	bool modifyLine = true;

	/**
	 */
	static CodeBuilder opCall(int indentedCount) {
		CodeBuilder b;
		b.indentCount = indentedCount;
		return b;
	}

	/**
	 * Places str into the buffer.
	 *
	 * put("text", Indent.open); will indent "text" at the current level and
	 * future code will be indented one level.
	 *
	 * put("other", Indent.close); will indent "other" at one less the current
	 * indentation.
	 *
	 * put("}{", Indent.close | Indent.open) will indent "}{" at one less the
	 * current indentation and continue indentation for future code.
	 *
	 * rawPut provides the same operations but does not include the current
	 * indentation level.
	 *
	 * To place indentation but no other code use put("");
	 *
	 * To reduce indentation without inserting code use put(Indent.close);
	 */
	void put(string str, Indent indent = Indent.none, string f = __FILE__, int l = __LINE__) {
		version(ModifyLine) if(modifyLine)
			upper ~= "#line " ~ l.to!string ~ " \"" ~ f ~ "\"\n";
		switch(str) {
			case "":
				if(!indent)
					goto default;
				goto case;
			case "\n":
				goto case;
			case "\r\n":
				rawPut(str, indent, f, l);
				break;
			default:
				if(indent & Indent.close) indentCount--;
				rawPut(indented(indentCount), Indent.none, f, l);
				rawPut(str, indent & Indent.open, f, l);
		}
	} unittest {
		/// Line numbers are added when using put
		auto code = CodeBuilder(0);

		mixin(`#line 0 "fake.file"
			  code.put("line");`);

		auto ans = code.finalize();

		assert(ans == "#line 0 \"fake.file\"\nline", ans);
	}


	/// ditto
	void rawPut(string str, Indent indent = Indent.none, string f = __FILE__, int l = __LINE__) {
		upper ~= str;
		put(indent);
	} unittest {
		/// Raw input does not insert indents
		auto code = CodeBuilder(1);

		code.rawPut("No indentation");

		auto ans = code.finalize();

		assert(ans == "No indentation", ans);
	}

	/// ditto
	void put(Indent indent) {
		assert(!(indent & Indent.close & Indent.open), "No-op indent");
		if(indent & Indent.close) indentCount--;
		if(indent & Indent.open) indentCount++;
	} unittest {
		auto code = CodeBuilder(0);
		code.modifyLine = false;
		code.put(Indent.open);
		code.put("Indented");
		assert(code.finalize().startsWith(indentation));
   }

	/**
	 * Places str onto a stack that can latter be popped into
	 * the current buffer.
	 *
	 * See put for specifics.
	 */
	void push(string str, Indent indent = Indent.close, string f = __FILE__, int l = __LINE__) {
		lower ~= [Operation(str, indent, false, f, l)];
	} unittest {
		auto code = CodeBuilder(0);
		code.modifyLine = false;
		code.push("}\n");
		code.push("b\n", Indent.none);
		code.push("{\n", Indent.open);
		assert(code.finalize() == "{\n\tb\n}\n", code.finalize());
	}

	/// ditto
	void push(Indent indent, string f = __FILE__, int l = __LINE__) {
		lower ~= [Operation(null, indent, false, f, l)];
	} unittest {
		auto code = CodeBuilder(0);
		code.modifyLine = false;
		code.push("b\n", Indent.none);
		code.push(Indent.open);
		code.push("{\n", Indent.none);
		assert(code.finalize() == "{\n\tb\n", code.finalize());
	}

	/// ditto
	void rawPush(string str, Indent indent = Indent.close, string f = __FILE__, int l = __LINE__) {
		lower ~= [Operation(str, indent, true, f, l)];
	} unittest {
		auto code = CodeBuilder(5);
		code.modifyLine = false;
		code.rawPush("b\n", Indent.none);
		code.push("{\n", Indent.open);
		assert(code.finalize() == "\t\t\t\t\t{\nb\n", code.finalize());
	}


	/**
	 * Places the top stack item into the buffer.
	 */
	void pop() {
		assert(!lower.empty(), "Can't pop empty buffer");

		foreach(op; lower.back())
			if(op.raw)
				rawPut(op.text, op.indent, op.file, op.line);
			else
				put(op.text, op.indent, op.file, op.line);

		lower.popBack();
		if(!__ctfe) assumeSafeAppend(lower);
	} unittest {
		auto code = CodeBuilder(0);
		code.modifyLine = false;
		code.put("{\n", Indent.open);
		code.push("}\n");
		code.pop();
		code.put("b\n");
		assert(code.finalize() == "{\n}\nb\n", code.finalize());
	}

	/**
	 * Construct a code string outside of the current buffer.
	 *
	 * Used to construct a code string in sequence, as apposed
	 * to pushing the desired code in reverse (making it harder
	 * to read).
	 *
	 * A build can also be saved with a name and later called.
	 */
	void build(string str, Indent indent = Indent.none, string f = __FILE__, int l = __LINE__) {
		store ~= Operation(str, indent, false, f, l);
	}

	/// ditto
	void build(Indent indent, string f = __FILE__, int l = __LINE__) {
		store ~= Operation(null, indent, false, f, l);
	}

	/// ditto
	void buildRaw(string str, Indent indent = Indent.none, string f = __FILE__, int l = __LINE__) {
		store ~= Operation(str, indent, true, f, l);
	}

	/**
	 * See push and put, performed on the current build.
	 */
	void pushBuild() {
		lower ~= store;
		store = null;
	}

	/// ditto
	void pushBuild(string name) {
		lower ~= saved[name];
	}

	/// ditto
	void putBuild(string name) {
		pushBuild(name);
		pop();
	}


	/**
	 * Stores the build to be called on later with $(B name).
	 */
	void saveBuild(string name) {
		saved[name] = store;
		store = null;
	}

	Memory mem() {
		Memory m;
		m.saved = saved;
		return m;
	}

	/**
	 * Adds the memory to this CodeBuilder
	 */
	void mem(Memory m) {
		saved = m.saved;
	}

	/**
	 * Returns the buffer, applying an code remaining on the stack.
	 */
	string finalize() {
		while(!lower.empty())
			pop();
		return upper;
	}
}

/// Example usage
unittest {
	auto indentCount = 0;
	auto code = CodeBuilder(indentCount);
	code.put("void main() {\n", Indent.open);
	code.push("}\n");
	code.put("int a = 5;\n");
	code.put("multiply(a);\n");
	code.pop();

	code.put("\nvoid multiply(int v) {\n", Indent.open);
	code.push("}\n");
	code.put("try {\n", Indent.open);
	code.build("} catch(Exception e) {\n", Indent.close | Indent.open);
	code.build("import std.stdio;\n");
	code.build("writeln(`Exception is bad but I don't care.`);\n");
	code.build("}\n", Indent.close);
	code.pushBuild();

	code.put("return v * ");
	code.rawPut(76.to!string ~ ";\n");
}
