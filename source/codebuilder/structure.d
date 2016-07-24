/**
 * Provides common functions during language conversion.
 */
module codebuilder.structure;

import std.algorithm;
import std.conv;
import std.range;
import std.regex;

/**
 * Specifies what string will be prepended for each indentation level.
 */
string indentation = "\t";
unittest {
	auto code = CodeBuilder(1);
	code.modifyLine = false;
	scope(exit) indentation = "\t";
	indentation = "    ";
	code.put("Hello");
	assert(code.finalize().startsWith("    "));
}

/**
 * Converts a numeric to an indent string
 */
string indented(int indentCount) {
    assert(indentCount > -1, "Indentation can never be less than 0.");
	if(__ctfe)
		return to!(string)(repeat("    ", indentCount).join.array);
	else
		return to!(string)(repeat(indentation, indentCount).join.array);
} unittest {
	static assert(indented(2) == "        ");
	assert(indented(2) == "\t\t");
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
	private Operation[] upper;
	private Operation[][] lower;

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
			upper ~= Operation("#line " ~ l.to!string ~ " \"" ~ f ~ "\"\n", Indent.none, true);
		upper ~= Operation(str, indent);
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
		upper ~= Operation(str, indent, true);
	} unittest {
		/// Raw input does not insert indents
		auto code = CodeBuilder(1);

		code.rawPut("No indentation");

		auto ans = code.finalize();

		assert(ans == "No indentation", ans);
	} unittest {
		/// Call finalization twice
		auto code = CodeBuilder(1);
		code.modifyLine = false;

		code.rawPut("No indentation\n");
		code.put("{\n", Indent.open);

		code.finalize();
		auto ans = code.finalize();

		assert(ans == "No indentation\n\t{\n", ans);
	}

	/// ditto
	void put(Indent indent) {
		assert(!(indent & Indent.close & Indent.open), "No-op indent");
		upper ~= Operation(null, indent);
	} unittest {
		auto code = CodeBuilder(0);
		code.modifyLine = false;
		code.put("No Indent");
		code.put(Indent.open);
		code.put("Indented");
		assert(!code.finalize().startsWith(indentation));
		assert(code.finalize() == "No Indent\tIndented", code.finalize());
   }

	/**
	 */
	void put(CodeBuilder build) {
		build.finalize();
		upper ~= build.upper;
	} unittest {
		// CodeBuilders can be added to each other
		auto code = CodeBuilder(5);
		code.modifyLine = false;
		code.put("a\n", Indent.open);
		code.put("b\n");
		code.put("c\n", Indent.close);
		auto code2 = CodeBuilder(0);
		code2.modifyLine = false;
		code2.put("{\n", Indent.open);
		code2.push("}\n", Indent.close);
		code2.put(code);
		assert(code2.finalize() == "{\n\ta\n\t\tb\n\tc\n}\n", code2.finalize());
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
	void rawPush(string str = null, Indent indent = Indent.close, string f = __FILE__, int l = __LINE__) {
		lower ~= [Operation(str, indent, true, f, l)];
	} unittest {
		auto code = CodeBuilder(5);
		code.modifyLine = false;
		code.rawPush("b\n", Indent.none);
		code.push("{\n", Indent.open);
		assert(code.finalize() == "\t\t\t\t\t{\nb\n", code.finalize());
	} unittest {
		auto code = CodeBuilder(0);
		code.modifyLine = false;
		code.put("{\n", Indent.open);
		if(true)
			code.rawPush();
		else
			code.push("b\n", Indent.none);
		code.pop();
		assert(code.finalize() == "{\n", code.finalize());
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
	 */
	void push(CodeBuilder build) {
		build.finalize();
		lower ~= build.upper;
	} unittest {
		// CodeBuilders can be added to each other
		auto code = CodeBuilder(5);
		code.modifyLine = false;
		code.put("a\n", Indent.open);
		code.put("b\n");
		code.put("c\n", Indent.close);
		auto code2 = CodeBuilder(0);
		code2.modifyLine = false;
		code2.put("{\n", Indent.open);
		code2.push("}\n", Indent.close);
		code2.push(code);
		assert(code2.finalize() == "{\n\ta\n\t\tb\n\tc\n}\n", code2.finalize());
	}

	/**
	 * Returns the buffer, applying an code remaining on the stack.
	 */
	string finalize() {
		while(!lower.empty)
			pop();
		string ans;
		int indentCount = indentCount;
		foreach(op; upper.save) {
			if(op.indent & Indent.close) indentCount--;
			if(!op.raw)
				ans ~= indented(indentCount);
			ans ~= op.text;
			if(op.indent & Indent.open) indentCount++;
		}
		return ans;
	}
}

unittest {
	// Compiletime capable
	string run() {
		auto code = CodeBuilder(1);
		code.modifyLine = false;
		code.put("Hello");
		code.rawPut(" World");
		return code.finalize();
	}

	static assert(run() == "    Hello World", run());
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
	auto catchblock = CodeBuilder(1);
	catchblock.put("} catch(Exception e) {\n", Indent.close | Indent.open);
	catchblock.put("import std.stdio;\n");
	catchblock.put("writeln(`Exception is bad but I don't care.`);\n");
	catchblock.put("}\n", Indent.close);
	code.push(catchblock);

	code.put("return v * ");
	code.rawPut(76.to!string ~ ";\n");
}
